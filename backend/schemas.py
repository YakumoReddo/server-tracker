from pydantic import BaseModel, EmailStr, Field
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

# 认证相关schemas
class AdminUserBase(BaseModel):
    username: str
    email: Optional[EmailStr] = None
    is_active: bool = True
    is_superuser: bool = False

class AdminUserCreate(AdminUserBase):
    password: str = Field(min_length=8)

class AdminUserUpdate(BaseModel):
    username: Optional[str] = None
    email: Optional[EmailStr] = None
    is_active: Optional[bool] = None
    is_superuser: Optional[bool] = None
    password: Optional[str] = Field(None, min_length=8)

class AdminUserResponse(AdminUserBase):
    id: int
    created_at: datetime
    updated_at: datetime
    last_login: Optional[datetime]

    class Config:
        from_attributes = True

class LoginRequest(BaseModel):
    username: str
    password: str

class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int

class TokenRefreshRequest(BaseModel):
    refresh_token: str

class CurrentUser(BaseModel):
    id: int
    username: str
    email: Optional[str]
    is_superuser: bool

# 探针管理schemas
class ProbeCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    host: str = Field(min_length=1, max_length=255)
    port: int = Field(default=22, ge=1, le=65535)
    description: Optional[str] = Field(default=None, max_length=500)
    server_url: str = Field(min_length=1)
    interval: int = Field(default=60, ge=30, le=3600)
    ports: List[int] = Field(default_factory=list)

class ProbeResponse(BaseModel):
    id: int
    name: str
    host: str
    port: int
    description: Optional[str]
    is_active: bool
    probe_key: str
    last_seen: Optional[datetime]
    created_at: datetime
    certificate_status: str
    certificate_expires: Optional[datetime]

    class Config:
        from_attributes = True

class ProbeUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    host: Optional[str] = Field(None, min_length=1, max_length=255)
    port: Optional[int] = Field(None, ge=1, le=65535)
    description: Optional[str] = Field(None, max_length=500)
    is_active: Optional[bool] = None
    interval: Optional[int] = Field(None, ge=30, le=3600)
    ports: Optional[List[int]] = None

class ProbeDownloadResponse(BaseModel):
    download_url: str
    expires_at: datetime

# 证书相关schemas
class CertificateInfo(BaseModel):
    id: int
    serial_number: str
    issued_at: datetime
    expires_at: datetime
    is_revoked: bool
    revoked_at: Optional[datetime]

    class Config:
        from_attributes = True

class CertificateRevocation(BaseModel):
    reason: str = Field(min_length=1, max_length=100)

# 数据签名schemas
class SignedMetricData(BaseModel):
    data: dict
    signature: str
    timestamp: str

class ProbeMetricSubmission(BaseModel):
    probe_key: str
    certificate: Optional[str] = None
    signed_data: SignedMetricData

# 审计日志schemas
class AuditLogResponse(BaseModel):
    id: int
    user_id: Optional[int]
    action: str
    resource: str
    resource_id: Optional[int]
    details: Optional[str]
    ip_address: Optional[str]
    user_agent: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True