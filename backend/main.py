from fastapi import FastAPI, HTTPException, Depends, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from database import SessionLocal, create_tables
from services import ServerManager, MetricCollector, AlertManager
from models import Server
from schemas import ServerCreate, ServerUpdate, MetricResponse, AlertResponse
from datetime import datetime
import json
import asyncio
from typing import List

create_tables()

app = FastAPI(title="ServerTracker API", description="服务器监测工具API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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

@app.get('/')
def read_root():
    return {"msg": "ServerTracker API running", "version": "1.0.0"}

@app.get('/api/servers')
async def get_servers(db: Session = Depends(get_db)):
    server_manager = ServerManager(db)
    servers = await server_manager.get_servers()
    return {"servers": servers}

@app.post('/api/servers')
async def create_server(server_data: ServerCreate, db: Session = Depends(get_db)):
    server_manager = ServerManager(db)
    server = await server_manager.create_server(server_data)
    return {"server": server}

@app.get('/api/servers/{server_id}')
async def get_server(server_id: int, db: Session = Depends(get_db)):
    server_manager = ServerManager(db)
    server = await server_manager.get_server(server_id)
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")
    return {"server": server}

@app.put('/api/servers/{server_id}')
async def update_server(server_id: int, server_data: ServerUpdate, db: Session = Depends(get_db)):
    server_manager = ServerManager(db)
    server = await server_manager.update_server(server_id, server_data)
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")
    return {"server": server}

@app.delete('/api/servers/{server_id}')
async def delete_server(server_id: int, db: Session = Depends(get_db)):
    server_manager = ServerManager(db)
    result = await server_manager.delete_server(server_id)
    return result

@app.get('/api/servers/{server_id}/metrics/latest')
async def get_latest_metrics(server_id: int, db: Session = Depends(get_db)):
    metric_collector = MetricCollector(db)
    metrics = await metric_collector.get_latest_metrics(server_id)
    if not metrics:
        raise HTTPException(status_code=404, detail="No metrics found")
    return {"metrics": metrics}

@app.get('/api/servers/{server_id}/metrics')
async def get_metrics(server_id: int, hours: int = 24, db: Session = Depends(get_db)):
    metric_collector = MetricCollector(db)
    metrics = await metric_collector.get_recent_metrics(server_id, hours)
    return {"metrics": metrics}

@app.post('/api/servers/{server_id}/metrics')
async def submit_metrics(server_id: int, metrics_data: dict, db: Session = Depends(get_db)):
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
async def probe_submit_metrics(probe_key: str, metrics_data: dict, db: Session = Depends(get_db)):
    server = db.query(Server).filter(Server.probe_key == probe_key).first()
    if not server:
        raise HTTPException(status_code=404, detail="Invalid probe key")
    
    metric_collector = MetricCollector(db)
    result = await metric_collector.save_metrics(server.id, metrics_data)
    
    await manager.broadcast({
        "type": "metrics_update",
        "server_id": server.id,
        "metrics": metrics_data,
        "timestamp": datetime.utcnow().isoformat()
    })
    
    return result

@app.get('/api/alerts/active')
async def get_active_alerts(db: Session = Depends(get_db)):
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

@app.get('/api/health')
def health_check():
    return {"status": "healthy", "timestamp": datetime.utcnow()}