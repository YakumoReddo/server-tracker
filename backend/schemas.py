from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class ServerBase(BaseModel):
    name: str
    host: str
    port: int = 22
    description: Optional[str] = None

class ServerCreate(ServerBase):
    pass

class ServerUpdate(BaseModel):
    name: Optional[str] = None
    host: Optional[str] = None
    port: Optional[int] = None
    description: Optional[str] = None
    is_active: Optional[bool] = None

class ServerResponse(ServerBase):
    id: int
    is_active: bool
    probe_key: str
    last_seen: Optional[datetime]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

class ServerMetricBase(BaseModel):
    cpu_usage: Optional[float] = None
    memory_usage: Optional[float] = None
    disk_usage: Optional[float] = None
    network_in: Optional[float] = None
    network_out: Optional[float] = None
    load_average: Optional[float] = None
    uptime: Optional[int] = None
    service_status: Optional[str] = None
    port_status: Optional[str] = None

class MetricResponse(ServerMetricBase):
    id: int
    server_id: int
    timestamp: datetime

    class Config:
        from_attributes = True

class AlertBase(BaseModel):
    level: str
    message: str
    metric_value: Optional[float] = None
    threshold: Optional[float] = None
    is_resolved: bool = False
    resolved_at: Optional[datetime] = None

class AlertResponse(AlertBase):
    id: int
    server_id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True