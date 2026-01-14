from fastapi import FastAPI, HTTPException, Depends, WebSocket, WebSocketDisconnect, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from database import SessionLocal, create_tables
from services import ServerManager, MetricCollector, AlertManager
from models import Server, AdminUser, ProbeCertificate, AuditLog
from schemas import (
    ServerCreate, ServerUpdate, MetricResponse, AlertResponse,
    AdminUserCreate, LoginRequest, TokenResponse, TokenRefreshRequest, CurrentUser,
    ProbeCreate, ProbeResponse, ProbeUpdate, ProbeDownloadResponse,
    CertificateRevocation, ProbeMetricSubmission, AuditLogResponse
)
from auth import AuthManager, SecurityManager
from certificate import CertificateManager, DataVerifier
from probe_manager import ProbeManager
from datetime import datetime, timedelta
import json
import asyncio
from typing import List, Optional
import secrets

create_tables()

app = FastAPI(title="ServerTracker API", description="服务器监测工具API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://localhost:3000", "https://127.0.0.1:3000"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)

security = HTTPBearer()
auth_manager = AuthManager()
security_manager = SecurityManager()
certificate_manager = CertificateManager()

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []
    
    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
    
    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
    
    async def broadcast(self, message: dict):
        for connection in list(self.active_connections):
            try:
                await connection.send_json(message)
            except:
                if connection in self.active_connections:
                    self.active_connections.remove(connection)

manager = ConnectionManager()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security), db: Session = Depends(get_db)):
    """获取当前用户"""
    try:
        payload = auth_manager.verify_token(credentials.credentials, "access")
        user_id = payload.get("sub")
        if user_id is None:
            raise HTTPException(status_code=401, detail="Invalid token")
        
        user = db.query(AdminUser).filter(AdminUser.id == user_id, AdminUser.is_active == True).first()
        if user is None:
            raise HTTPException(status_code=401, detail="User not found")
        
        return user
    except:
        raise HTTPException(status_code=401, detail="Invalid token")

def log_action(db: Session, user_id: Optional[int], action: str, resource: str, 
               resource_id: Optional[int] = None, details: Optional[str] = None,
               request: Optional[Request] = None):
    """记录审计日志"""
    if user_id is not None and hasattr(user_id, 'id'):
        user_id = user_id.id
    
    audit_log = AuditLog(
        user_id=user_id,
        action=action,
        resource=resource,
        resource_id=resource_id,
        details=details,
        ip_address=request.client.host if request and request.client else None,
        user_agent=request.headers.get("User-Agent") if request else None
    )
    db.add(audit_log)
    db.commit()

@app.post('/api/auth/login')
def login(login_data: LoginRequest, db: Session = Depends(get_db), request: Request = None):
    """管理员登录"""
    user = db.query(AdminUser).filter(
        AdminUser.username == login_data.username,
        AdminUser.is_active == True
    ).first()
    
    if not user or not auth_manager.verify_password(login_data.password, user.password_hash):
        log_action(db, None, "login_failed", "auth", details=f"Failed login attempt for {login_data.username}", request=request)
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    access_token = auth_manager.create_access_token({"sub": str(user.id), "username": user.username})
    refresh_token = auth_manager.create_refresh_token({"sub": str(user.id)})
    
    user.last_login = datetime.utcnow()
    db.commit()
    
    log_action(db, user, "login_success", "auth", details="User logged in successfully", request=request)
    
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "expires_in": 1800
    }

@app.post('/api/auth/refresh')
def refresh_token(refresh_data: TokenRefreshRequest, db: Session = Depends(get_db)):
    """刷新令牌"""
    try:
        payload = auth_manager.verify_token(refresh_data.refresh_token, "refresh")
        user_id = payload.get("sub")
        
        user = db.query(AdminUser).filter(AdminUser.id == user_id, AdminUser.is_active == True).first()
        if not user:
            raise HTTPException(status_code=401, detail="User not found")
        
        new_access_token = auth_manager.create_access_token({"sub": str(user.id), "username": user.username})
        
        return {
            "access_token": new_access_token,
            "token_type": "bearer",
            "expires_in": 1800
        }
    except:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

@app.get('/api/auth/me')
def get_current_user_info(current_user: AdminUser = Depends(get_current_user)):
    """获取当前用户信息"""
    return {
        "id": current_user.id,
        "username": current_user.username,
        "email": current_user.email,
        "is_superuser": current_user.is_superuser
    }

@app.get('/api/servers')
async def get_servers(db: Session = Depends(get_db), current_user: AdminUser = Depends(get_current_user)):
    server_manager = ServerManager(db)
    servers = await server_manager.get_servers()
    log_action(db, current_user.id, "view", "servers")
    return {"servers": servers}

@app.post('/api/servers')
async def create_server(server_data: ServerCreate, db: Session = Depends(get_db), 
                       current_user: AdminUser = Depends(get_current_user)):
    server_manager = ServerManager(db)
    server = await server_manager.create_server(server_data)
    log_action(db, current_user.id, "create", "servers", server.id, f"Created server {server.name}")
    return {"server": server}

@app.get('/api/servers/{server_id}')
async def get_server(server_id: int, db: Session = Depends(get_db), 
                    current_user: AdminUser = Depends(get_current_user)):
    server_manager = ServerManager(db)
    server = await server_manager.get_server(server_id)
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")
    log_action(db, current_user.id, "view", "servers", server_id)
    return {"server": server}

@app.put('/api/servers/{server_id}')
async def update_server(server_id: int, server_data: ServerUpdate, db: Session = Depends(get_db),
                       current_user: AdminUser = Depends(get_current_user)):
    server_manager = ServerManager(db)
    server = await server_manager.update_server(server_id, server_data)
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")
    log_action(db, current_user.id, "update", "servers", server_id, f"Updated server")
    return {"server": server}

@app.delete('/api/servers/{server_id}')
async def delete_server(server_id: int, db: Session = Depends(get_db),
                       current_user: AdminUser = Depends(get_current_user)):
    server_manager = ServerManager(db)
    result = await server_manager.delete_server(server_id)
    log_action(db, current_user.id, "delete", "servers", server_id, f"Deleted server {server_id}")
    return result

@app.get('/api/servers/{server_id}/metrics/latest')
async def get_latest_metrics(server_id: int, db: Session = Depends(get_db),
                           current_user: AdminUser = Depends(get_current_user)):
    metric_collector = MetricCollector(db)
    metrics = await metric_collector.get_latest_metrics(server_id)
    if not metrics:
        raise HTTPException(status_code=404, detail="No metrics found")
    return {"metrics": metrics}

@app.get('/api/servers/{server_id}/metrics')
async def get_metrics(server_id: int, hours: int = 24, db: Session = Depends(get_db),
                     current_user: AdminUser = Depends(get_current_user)):
    metric_collector = MetricCollector(db)
    metrics = await metric_collector.get_recent_metrics(server_id, hours)
    return {"metrics": metrics}

@app.post('/api/servers/{server_id}/metrics')
async def submit_metrics(server_id: int, metrics_data: dict, db: Session = Depends(get_db),
                        current_user: AdminUser = Depends(get_current_user)):
    server = db.query(Server).filter(Server.id == server_id).first()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")
    
    metric_collector = MetricCollector(db)
    result = await metric_collector.save_metrics(server_id, metrics_data)
    
    await manager.broadcast({
        "type": "metrics_update",
        "server_id": server_id,
        "metrics": metrics_data,
        "timestamp": datetime.utcnow().isoformat()
    })
    
    return result

@app.post('/api/probe/{probe_key}/metrics')
async def probe_submit_metrics(probe_key: str, submission: ProbeMetricSubmission, db: Session = Depends(get_db)):
    """安全的探针数据提交"""
    try:
        server = db.query(Server).filter(Server.probe_key == probe_key).first()
        if not server:
            raise HTTPException(status_code=404, detail="Invalid probe key")
        
        # 验证证书和签名
        probe_manager = ProbeManager(db)
        if not probe_manager.verify_probe_signature(probe_key, submission.signed_data, submission.certificate):
            raise HTTPException(status_code=401, detail="Invalid signature or certificate")
        
        # 保存指标数据
        metric_collector = MetricCollector(db)
        result = await metric_collector.save_metrics(server.id, submission.signed_data["data"])
        
        await manager.broadcast({
            "type": "metrics_update",
            "server_id": server.id,
            "metrics": submission.signed_data["data"],
            "timestamp": datetime.utcnow().isoformat()
        })
        
        return result
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid data: {str(e)}")

@app.get('/api/alerts/active')
async def get_active_alerts(db: Session = Depends(get_db), current_user: AdminUser = Depends(get_current_user)):
    alert_manager = AlertManager(db)
    alerts = await alert_manager.get_active_alerts()
    return {"alerts": alerts}

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)