from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime

from database import get_db
from models import Server, AdminUser, ProbeCertificate, ProbeDownload, AuditLog
from schemas import (
    ProbeCreate, ProbeResponse, ProbeUpdate, ProbeDownloadResponse,
    CurrentUser
)
from auth import AuthManager, SecurityManager
from certificate import CertificateManager, DataVerifier
from probe_manager import ProbeManager
from services import ServerManager, MetricCollector, AlertManager

router = APIRouter(prefix="/api/admin", tags=["admin"])

security = HTTPBearer()
auth_manager = AuthManager()
security_manager = SecurityManager()
certificate_manager = CertificateManager()

def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security), db: Session = Depends(get_db)):
    """获取当前用户"""
    try:
        payload = auth_manager.verify_token(credentials.credentials, "access")
        user_id = int(payload.get("sub"))
        if user_id is None:
            raise HTTPException(status_code=401, detail="Invalid token")
        
        user = db.query(AdminUser).filter(AdminUser.id == user_id, AdminUser.is_active == True).first()
        if user is None:
            raise HTTPException(status_code=401, detail="User not found")
        
        return user
    except:
        raise HTTPException(status_code=401, detail="Invalid token")

def log_action(db: Session, user: Optional[AdminUser], action: str, resource: str, 
               resource_id: Optional[int] = None, details: Optional[str] = None,
               request: Optional[Request] = None):
    """记录审计日志"""
    user_id = user.id if user else None
    
    audit_log = AuditLog(
        user_id=user_id,
        action=action,
        resource=resource,
        resource_id=resource_id,
        details=details,
        ip_address=request.client.host if request and hasattr(request.client, 'host') else None,
        user_agent=request.headers.get("User-Agent") if request else None
    )
    db.add(audit_log)
    db.commit()

@router.get("/probes", response_model=List[ProbeResponse])
async def get_probes(db: Session = Depends(get_db), current_user: AdminUser = Depends(get_current_user)):
    """获取探针列表"""
    probe_manager = ProbeManager(db)
    probes = probe_manager.get_probes()
    log_action(db, current_user, "view", "probes")
    return probes

@router.post("/probes", response_model=ProbeResponse)
async def create_probe(probe_data: ProbeCreate, db: Session = Depends(get_db), 
                      current_user: AdminUser = Depends(get_current_user)):
    """创建新探针"""
    probe_manager = ProbeManager(db)
    server, certificate = probe_manager.create_probe(probe_data.dict())
    
    log_action(db, current_user, "create", "probes", server.id, f"Created probe {server.name}")
    
    return {
        'id': server.id,
        'name': server.name,
        'host': server.host,
        'port': server.port,
        'description': server.description,
        'is_active': server.is_active,
        'probe_key': server.probe_key,
        'last_seen': server.last_seen,
        'created_at': server.created_at,
        'certificate_status': '有效',
        'certificate_expires': certificate.expires_at
    }

@router.get("/probes/{probe_id}", response_model=ProbeResponse)
async def get_probe(probe_id: int, db: Session = Depends(get_db), 
                   current_user: AdminUser = Depends(get_current_user)):
    """获取探针详情"""
    probe_manager = ProbeManager(db)
    probe = probe_manager.get_probe(probe_id)
    
    if not probe:
        raise HTTPException(status_code=404, detail="Probe not found")
    
    log_action(db, current_user, "view", "probes", probe_id)
    return probe

@router.put("/probes/{probe_id}", response_model=ProbeResponse)
async def update_probe(probe_id: int, update_data: ProbeUpdate, db: Session = Depends(get_db),
                      current_user: AdminUser = Depends(get_current_user)):
    """更新探针信息"""
    probe_manager = ProbeManager(db)
    server = probe_manager.update_probe(probe_id, update_data.dict(exclude_unset=True))
    
    if not server:
        raise HTTPException(status_code=404, detail="Probe not found")
    
    log_action(db, current_user, "update", "probes", probe_id, f"Updated probe")
    
    return {
        'id': server.id,
        'name': server.name,
        'host': server.host,
        'port': server.port,
        'description': server.description,
        'is_active': server.is_active,
        'probe_key': server.probe_key,
        'last_seen': server.last_seen,
        'created_at': server.created_at,
        'certificate_status': '有效',
        'certificate_expires': None
    }

@router.delete("/probes/{probe_id}")
async def delete_probe(probe_id: int, db: Session = Depends(get_db),
                      current_user: AdminUser = Depends(get_current_user)):
    """删除探针并吊销证书"""
    probe_manager = ProbeManager(db)
    result = probe_manager.delete_probe(probe_id)
    
    if not result:
        raise HTTPException(status_code=404, detail="Probe not found")
    
    log_action(db, current_user, "delete", "probes", probe_id, f"Deleted probe {probe_id}")
    return {"message": "Probe deleted and certificate revoked"}

@router.post("/probes/{probe_id}/package", response_model=ProbeDownloadResponse)
async def generate_probe_package(probe_id: int, db: Session = Depends(get_db),
                                current_user: AdminUser = Depends(get_current_user)):
    """生成探针安装包"""
    probe_manager = ProbeManager(db)
    try:
        package_info = probe_manager.generate_probe_package(probe_id)
        log_action(db, current_user, "download_package", "probes", probe_id, "Generated probe package")
        
        return {
            'download_url': f"/api/admin/downloads/{package_info['download_token']}",
            'expires_at': package_info['expires_at']
        }
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

@router.get("/downloads/{download_token}")
async def download_probe_package(download_token: str, db: Session = Depends(get_db)):
    """下载探针包"""
    download_record = db.query(ProbeDownload).filter(
        ProbeDownload.download_token == download_token
    ).first()
    
    if not download_record:
        raise HTTPException(status_code=404, detail="Download token not found")
    
    if download_record.is_used or datetime.utcnow() > download_record.expires_at:
        raise HTTPException(status_code=410, detail="Download link expired")
    
    # 标记为已使用
    download_record.is_used = True
    db.commit()
    
    # 这里应该返回实际的文件内容
    # 暂时返回下载信息
    return {"message": "Package downloaded successfully", "filename": f"probe_package.tar.gz"}

@router.get("/audit-logs", response_model=List[dict])
async def get_audit_logs(db: Session = Depends(get_db), current_user: AdminUser = Depends(get_current_user)):
    """获取审计日志"""
    if not current_user.is_superuser:
        raise HTTPException(status_code=403, detail="Superuser access required")
    
    logs = db.query(AuditLog).order_by(AuditLog.created_at.desc()).limit(100).all()
    
    return [{
        'id': log.id,
        'user_id': log.user_id,
        'action': log.action,
        'resource': log.resource,
        'resource_id': log.resource_id,
        'details': log.details,
        'ip_address': log.ip_address,
        'user_agent': log.user_agent,
        'created_at': log.created_at
    } for log in logs]

@router.get("/users", response_model=List[dict])
async def get_users(db: Session = Depends(get_db), current_user: AdminUser = Depends(get_current_user)):
    """获取用户列表"""
    if not current_user.is_superuser:
        raise HTTPException(status_code=403, detail="Superuser access required")
    
    users = db.query(AdminUser).all()
    
    return [{
        'id': user.id,
        'username': user.username,
        'email': user.email,
        'is_active': user.is_active,
        'is_superuser': user.is_superuser,
        'created_at': user.created_at,
        'last_login': user.last_login
    } for user in users]

@router.post("/users")
async def create_user(user_data: dict, db: Session = Depends(get_db), 
                     current_user: AdminUser = Depends(get_current_user)):
    """创建用户"""
    if not current_user.is_superuser:
        raise HTTPException(status_code=403, detail="Superuser access required")
    
    # 检查用户名是否已存在
    existing_user = db.query(AdminUser).filter(AdminUser.username == user_data['username']).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Username already exists")
    
    # 创建新用户
    hashed_password = auth_manager.get_password_hash(user_data['password'])
    
    new_user = AdminUser(
        username=user_data['username'],
        password_hash=hashed_password,
        email=user_data.get('email'),
        is_active=user_data.get('is_active', True),
        is_superuser=user_data.get('is_superuser', False)
    )
    
    db.add(new_user)
    db.commit()
    
    log_action(db, current_user, "create", "users", new_user.id, f"Created user {new_user.username}")
    
    return {"message": "User created successfully", "user_id": new_user.id}