from sqlalchemy.orm import Session
from models import Server, ServerMetric, Alert
from schemas import ServerCreate, ServerUpdate, ServerResponse, MetricResponse, AlertResponse
from datetime import datetime, timedelta
import json
import uuid

class ServerManager:
    def __init__(self, db: Session):
        self.db = db

    async def create_server(self, server_data: ServerCreate) -> ServerResponse:
        probe_key = str(uuid.uuid4())
        
        db_server = Server(
            name=server_data.name,
            host=server_data.host,
            port=server_data.port,
            description=server_data.description,
            probe_key=probe_key
        )
        
        self.db.add(db_server)
        self.db.commit()
        self.db.refresh(db_server)
        
        return ServerResponse(
            id=db_server.id,
            name=db_server.name,
            host=db_server.host,
            port=db_server.port,
            description=db_server.description,
            is_active=db_server.is_active,
            probe_key=db_server.probe_key,
            last_seen=db_server.last_seen,
            created_at=db_server.created_at,
            updated_at=db_server.updated_at
        )

    async def get_servers(self, skip: int = 0, limit: int = 100) -> list[ServerResponse]:
        servers = self.db.query(Server).offset(skip).limit(limit).all()
        return [
            ServerResponse(
                id=server.id,
                name=server.name,
                host=server.host,
                port=server.port,
                description=server.description,
                is_active=server.is_active,
                probe_key=server.probe_key,
                last_seen=server.last_seen,
                created_at=server.created_at,
                updated_at=server.updated_at
            )
            for server in servers
        ]

    async def get_server(self, server_id: int) -> ServerResponse | None:
        server = self.db.query(Server).filter(Server.id == server_id).first()
        if not server:
            return None
        
        return ServerResponse(
            id=server.id,
            name=server.name,
            host=server.host,
            port=server.port,
            description=server.description,
            is_active=server.is_active,
            probe_key=server.probe_key,
            last_seen=server.last_seen,
            created_at=server.created_at,
            updated_at=server.updated_at
        )

    async def update_server(self, server_id: int, server_data: ServerUpdate) -> ServerResponse | None:
        server = self.db.query(Server).filter(Server.id == server_id).first()
        if not server:
            return None
        
        update_data = server_data.dict(exclude_unset=True)
        for field, value in update_data.items():
            setattr(server, field, value)
        
        self.db.commit()
        self.db.refresh(server)
        
        return ServerResponse(
            id=server.id,
            name=server.name,
            host=server.host,
            port=server.port,
            description=server.description,
            is_active=server.is_active,
            probe_key=server.probe_key,
            last_seen=server.last_seen,
            created_at=server.created_at,
            updated_at=server.updated_at
        )

    async def delete_server(self, server_id: int) -> dict:
        server = self.db.query(Server).filter(Server.id == server_id).first()
        if not server:
            return {"status": "error", "message": "Server not found"}
        
        self.db.delete(server)
        self.db.commit()
        return {"status": "success", "message": "Server deleted"}

class MetricCollector:
    def __init__(self, db: Session):
        self.db = db

    async def save_metrics(self, server_id: int, metrics_data: dict) -> dict:
        db_metric = ServerMetric(
            server_id=server_id,
            cpu_usage=metrics_data.get('cpu_usage'),
            memory_usage=metrics_data.get('memory_usage'),
            disk_usage=metrics_data.get('disk_usage'),
            network_in=metrics_data.get('network_in'),
            network_out=metrics_data.get('network_out'),
            load_average=metrics_data.get('load_average'),
            uptime=metrics_data.get('uptime'),
            service_status=json.dumps(metrics_data.get('service_status', {})),
            port_status=json.dumps(metrics_data.get('port_status', {}))
        )
        
        self.db.add(db_metric)
        
        # 更新服务器最后活跃时间
        server = self.db.query(Server).filter(Server.id == server_id).first()
        if server:
            server.last_seen = datetime.utcnow()
        
        self.db.commit()
        return {"status": "success", "id": db_metric.id}

    async def get_recent_metrics(self, server_id: int, hours: int = 24) -> list[MetricResponse]:
        since = datetime.utcnow() - timedelta(hours=hours)
        metrics = self.db.query(ServerMetric).filter(
            ServerMetric.server_id == server_id,
            ServerMetric.timestamp >= since
        ).order_by(ServerMetric.timestamp.desc()).limit(100).all()
        
        return [
            MetricResponse(
                id=metric.id,
                server_id=metric.server_id,
                cpu_usage=metric.cpu_usage,
                memory_usage=metric.memory_usage,
                disk_usage=metric.disk_usage,
                network_in=metric.network_in,
                network_out=metric.network_out,
                load_average=metric.load_average,
                uptime=metric.uptime,
                service_status=metric.service_status,
                port_status=metric.port_status,
                timestamp=metric.timestamp
            )
            for metric in metrics
        ]

    async def get_latest_metrics(self, server_id: int) -> MetricResponse | None:
        metric = self.db.query(ServerMetric).filter(
            ServerMetric.server_id == server_id
        ).order_by(ServerMetric.timestamp.desc()).first()
        
        if not metric:
            return None
        
        return MetricResponse(
            id=metric.id,
            server_id=metric.server_id,
            cpu_usage=metric.cpu_usage,
            memory_usage=metric.memory_usage,
            disk_usage=metric.disk_usage,
            network_in=metric.network_in,
            network_out=metric.network_out,
            load_average=metric.load_average,
            uptime=metric.uptime,
            service_status=metric.service_status,
            port_status=metric.port_status,
            timestamp=metric.timestamp
        )

class AlertManager:
    def __init__(self, db: Session):
        self.db = db

    async def get_active_alerts(self) -> list[AlertResponse]:
        alerts = self.db.query(Alert).filter(Alert.is_resolved == False).all()
        return [
            AlertResponse(
                id=alert.id,
                server_id=alert.server_id,
                level=alert.level,
                message=alert.message,
                metric_value=alert.metric_value,
                threshold=alert.threshold,
                is_resolved=alert.is_resolved,
                resolved_at=alert.resolved_at,
                created_at=alert.created_at,
                updated_at=alert.updated_at
            )
            for alert in alerts
        ]