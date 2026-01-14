from sqlalchemy.orm import Session
from typing import List, Optional, Dict, Tuple
from datetime import datetime, timedelta
import uuid
import secrets
import tarfile
import tempfile
import os
import json
from pathlib import Path

from models import Server, ProbeCertificate, ProbeDownload
from auth import SecurityManager
from certificate import CertificateManager, DataVerifier

class ProbeManager:
    """探针管理器"""
    
    def __init__(self, db: Session):
        self.db = db
        self.security_manager = SecurityManager()
        self.certificate_manager = CertificateManager()
    
    def create_probe(self, probe_data: Dict) -> Tuple[Server, ProbeCertificate]:
        """创建新探针"""
        # 生成唯一probe_key
        probe_key = self.security_manager.generate_probe_key()
        
        # 创建服务器记录
        server = Server(
            name=probe_data['name'],
            host=probe_data['host'],
            port=probe_data['port'],
            description=probe_data.get('description'),
            probe_key=probe_key,
            is_active=True
        )
        
        self.db.add(server)
        self.db.flush()  # 获取server.id
        
        # 生成证书
        cert_data = self.certificate_manager.generate_probe_certificate({
            'name': probe_data['name'],
            'host': probe_data['host'],
            'ip_address': '127.0.0.1'  # 默认IP，后续可更新
        })
        
        # 存储证书
        certificate = ProbeCertificate(
            server_id=server.id,
            certificate_pem=cert_data['certificate'],
            private_key_pem=cert_data['private_key'],
            public_key_pem=cert_data['public_key'],
            serial_number=cert_data['serial_number'],
            expires_at=datetime.utcnow() + timedelta(days=365)
        )
        
        self.db.add(certificate)
        self.db.commit()
        
        return server, certificate
    
    def get_probes(self) -> List[Dict]:
        """获取探针列表"""
        servers = self.db.query(Server).all()
        probes = []
        
        for server in servers:
            cert = self.db.query(ProbeCertificate).filter(
                ProbeCertificate.server_id == server.id
            ).first()
            
            probes.append({
                'id': server.id,
                'name': server.name,
                'host': server.host,
                'port': server.port,
                'description': server.description,
                'is_active': server.is_active,
                'probe_key': server.probe_key,
                'last_seen': server.last_seen,
                'created_at': server.created_at,
                'certificate_status': self._get_certificate_status(cert),
                'certificate_expires': cert.expires_at if cert else None
            })
        
        return probes
    
    def get_probe(self, probe_id: int) -> Optional[Dict]:
        """获取单个探针信息"""
        server = self.db.query(Server).filter(Server.id == probe_id).first()
        if not server:
            return None
        
        cert = self.db.query(ProbeCertificate).filter(
            ProbeCertificate.server_id == server.id
        ).first()
        
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
            'certificate_status': self._get_certificate_status(cert),
            'certificate_expires': cert.expires_at if cert else None,
            'certificate': cert.certificate_pem if cert else None,
            'private_key': cert.private_key_pem if cert else None
        }
    
    def update_probe(self, probe_id: int, update_data: Dict) -> Optional[Server]:
        """更新探针信息"""
        server = self.db.query(Server).filter(Server.id == probe_id).first()
        if not server:
            return None
        
        for field, value in update_data.items():
            if hasattr(server, field) and value is not None:
                setattr(server, field, value)
        
        server.updated_at = datetime.utcnow()
        self.db.commit()
        return server
    
    def delete_probe(self, probe_id: int) -> bool:
        """删除探针并吊销证书"""
        server = self.db.query(Server).filter(Server.id == probe_id).first()
        if not server:
            return False
        
        # 吊销证书
        cert = self.db.query(ProbeCertificate).filter(
            ProbeCertificate.server_id == server.id
        ).first()
        
        if cert:
            cert.is_revoked = True
            cert.revoked_at = datetime.utcnow()
        
        # 删除服务器记录
        self.db.delete(server)
        self.db.commit()
        
        return True
    
    def generate_probe_package(self, probe_id: int) -> Dict:
        """生成探针安装包"""
        server = self.db.query(Server).filter(Server.id == probe_id).first()
        if not server:
            raise ValueError("Probe not found")
        
        cert = self.db.query(ProbeCertificate).filter(
            ProbeCertificate.server_id == server.id
        ).first()
        
        if not cert:
            raise ValueError("Certificate not found")
        
        # 生成下载token
        download_token = secrets.token_urlsafe(32)
        expires_at = datetime.utcnow() + timedelta(hours=24)
        
        download_record = ProbeDownload(
            server_id=probe_id,
            download_token=download_token,
            expires_at=expires_at
        )
        
        self.db.add(download_record)
        self.db.commit()
        
        # 准备配置文件
        probe_config = {
            "server_url": "https://your-domain.com",
            "probe_key": server.probe_key,
            "probe_id": server.id,
            "interval": 60,
            "ports": [80, 443, 22, 3306],
            "certificate_file": "probe.crt",
            "private_key_file": "private_key.pem"
        }
        
        # 创建临时文件包
        temp_dir = tempfile.mkdtemp()
        package_files = {
            'server_probe.py': self._get_probe_script(),
            'probe_config.json': json.dumps(probe_config, indent=2),
            'probe.crt': cert.certificate_pem,
            'private_key.pem': cert.private_key_pem,
            'requirements.txt': 'requests\npsutil\ncryptography\n',
            'README.md': self._get_readme_content(server.name)
        }
        
        # 写入文件
        for filename, content in package_files.items():
            file_path = os.path.join(temp_dir, filename)
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
        
        # 创建tar.gz包
        package_path = os.path.join(temp_dir, f"probe_package_{server.name}.tar.gz")
        with tarfile.open(package_path, "w:gz") as tar:
            for filename in package_files.keys():
                file_path = os.path.join(temp_dir, filename)
                tar.add(file_path, arcname=filename)
        
        # 清理临时文件
        for filename in package_files.keys():
            os.remove(os.path.join(temp_dir, filename))
        
        return {
            'download_token': download_token,
            'expires_at': expires_at,
            'package_path': package_path
        }
    
    def _get_certificate_status(self, cert: Optional[ProbeCertificate]) -> str:
        """获取证书状态"""
        if not cert:
            return "无证书"
        
        if cert.is_revoked:
            return "已吊销"
        
        if datetime.utcnow() > cert.expires_at:
            return "已过期"
        
        days_left = (cert.expires_at - datetime.utcnow()).days
        if days_left < 30:
            return f"即将过期({days_left}天)"
        
        return "有效"
    
    def _get_probe_script(self) -> str:
        """获取升级后的探针脚本内容"""
        # 这里返回升级后的SecureServerProbe脚本
        return '''#!/usr/bin/env python3
import os
import time
import json
import requests
import psutil
import socket
import hmac
import hashlib
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class SecureServerProbe:
    def __init__(self, config_file: str = "probe_config.json"):
        self.config = self.load_config(config_file)
        self.server_url = self.config.get("server_url")
        self.probe_key = self.config.get("probe_key")
        self.probe_id = self.config.get("probe_id")
        self.interval = self.config.get("interval", 60)
        
        self.certificate_file = self.config.get("certificate_file", "probe.crt")
        self.private_key_file = self.config.get("private_key_file", "private_key.pem")
        
        self.private_key = self.load_private_key()
    
    def load_config(self, config_file: str) -> dict:
        with open(config_file, 'r') as f:
            return json.load(f)
    
    def load_private_key(self) -> str:
        with open(self.private_key_file, 'r') as f:
            return f.read()
    
    def sign_data(self, data: dict) -> dict:
        sorted_data = json.dumps(data, sort_keys=True)
        signature = hmac.new(
            self.private_key.encode(),
            sorted_data.encode(),
            hashlib.sha256
        ).hexdigest()
        return {
            "data": data,
            "signature": signature,
            "timestamp": datetime.utcnow().isoformat()
        }
    
    def collect_system_metrics(self) -> dict:
        try:
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk_usage = psutil.disk_usage('/')
            
            return {
                "cpu_usage": round(cpu_percent, 2),
                "memory_usage": round(memory.percent, 2),
                "disk_usage": round((disk_usage.used / disk_usage.total) * 100, 2),
                "uptime": int(time.time() - psutil.boot_time()),
                "probe_id": self.probe_id,
                "probe_key": self.probe_key
            }
        except Exception as e:
            logger.error(f"Error collecting metrics: {e}")
            return {}
    
    def send_metrics(self, metrics: dict) -> bool:
        try:
            signed_data = self.sign_data(metrics)
            url = f"{self.server_url}/api/probe/{self.probe_key}/metrics"
            payload = {'probe_key': self.probe_key, 'signed_data': signed_data}
            
            response = requests.post(url, json=payload, timeout=10)
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Error sending metrics: {e}")
            return False
    
    def run(self):
        logger.info(f"Starting secure probe with interval {self.interval}s")
        while True:
            try:
                metrics = self.collect_system_metrics()
                if metrics:
                    self.send_metrics(metrics)
            except Exception as e:
                logger.error(f"Error in main loop: {e}")
            time.sleep(self.interval)

if __name__ == "__main__":
    probe = SecureServerProbe()
    probe.run()
'''
    
    def _get_readme_content(self, probe_name: str) -> str:
        """获取README内容"""
        return f'''# ServerTracker Probe - {probe_name}

## 安装说明

### 系统要求
- Python 3.7+
- Linux/Windows/macOS

### 安装步骤

1. 解压安装包：
```bash
tar -xzf probe_package_{probe_name}.tar.gz
cd probe_package_{probe_name}
```

2. 安装依赖：
```bash
pip3 install -r requirements.txt
```

3. 配置权限：
```bash
chmod 600 private_key.pem
chmod 644 *.crt *.json server_probe.py
```

4. 运行探针：
```bash
python3 server_probe.py
```

### 系统服务 (可选)

创建systemd服务：
```bash
sudo cp server_probe.py /usr/local/bin/
sudo cp probe_config.json /etc/servertracker/
sudo cp probe.crt /etc/servertracker/
sudo cp private_key.pem /etc/servertracker/
sudo chmod 600 /etc/servertracker/private_key.pem

sudo cat > /etc/systemd/system/servertracker-probe.service << EOF
[Unit]
Description=ServerTracker Probe - {probe_name}
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/server_probe.py --config /etc/servertracker/probe_config.json
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable servertracker-probe
sudo systemctl start servertracker-probe
```

### 配置说明

编辑 `probe_config.json` 文件修改以下参数：
- `server_url`: 服务器地址
- `interval`: 采集间隔(秒)
- `ports`: 监控的端口列表

### 故障排除

1. 检查日志：
```bash
journalctl -u servertracker-probe -f
```

2. 手动测试：
```bash
python3 server_probe.py --test
```

### 安全说明

- 私钥文件权限设置为600，只能被root访问
- 探针使用HMAC签名确保数据传输安全
- 证书有效期为1年，到期前请更新

### 支持

如有问题，请联系管理员。
'''
    
    def verify_probe_signature(self, probe_key: str, signed_data: Dict, certificate: str) -> bool:
        """验证探针签名"""
        try:
            # 获取探针信息
            server = self.db.query(Server).filter(Server.probe_key == probe_key).first()
            if not server:
                return False
            
            # 获取对应证书
            cert = self.db.query(ProbeCertificate).filter(
                ProbeCertificate.server_id == server.id,
                ProbeCertificate.is_revoked == False
            ).first()
            
            if not cert:
                return False
            
            # 验证证书
            if not self.certificate_manager.verify_certificate(certificate):
                return False
            
            # 验证签名
            verifier = DataVerifier(cert.public_key_pem)
            return verifier.verify_signature(signed_data)
            
        except Exception:
            return False