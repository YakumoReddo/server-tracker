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
from cryptography import x509
from cryptography.hazmat.primitives import serialization

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class SecureServerProbe:
    def __init__(self, config_file: str = "probe_config.json"):
        self.config = self.load_config(config_file)
        self.server_url = self.config.get("server_url", "http://localhost:8000")
        self.probe_key = self.config.get("probe_key")
        self.probe_id = self.config.get("probe_id")
        self.interval = self.config.get("interval", 60)
        
        # 加载证书和私钥
        self.certificate_file = self.config.get("certificate_file", "probe.crt")
        self.private_key_file = self.config.get("private_key_file", "private_key.pem")
        
        self.private_key = self.load_private_key()
        
        if not self.probe_key:
            raise ValueError("probe_key is required")
    
    def load_config(self, config_file: str) -> dict:
        if os.path.exists(config_file):
            with open(config_file, 'r') as f:
                return json.load(f)
        else:
            default_config = {
                "server_url": "http://localhost:8000",
                "probe_key": "",
                "probe_id": None,
                "interval": 60,
                "ports": [],
                "certificate_file": "probe.crt",
                "private_key_file": "private_key.pem"
            }
            with open(config_file, 'w') as f:
                json.dump(default_config, f, indent=2)
            return default_config
    
    def load_private_key(self) -> str:
        if os.path.exists(self.private_key_file):
            with open(self.private_key_file, 'r') as f:
                return f.read()
        else:
            raise FileNotFoundError(f"Private key file not found: {self.private_key_file}")
    
    def load_certificate(self) -> str:
        if os.path.exists(self.certificate_file):
            with open(self.certificate_file, 'r') as f:
                return f.read()
        else:
            raise FileNotFoundError(f"Certificate file not found: {self.certificate_file}")
    
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
    
    def check_port_status(self, ports: list) -> dict:
        port_status = {}
        for port in ports:
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(1)
                result = sock.connect_ex(('localhost', port))
                port_status[str(port)] = result == 0
                sock.close()
            except:
                port_status[str(port)] = False
        return port_status
    
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
    
    def collect_all_metrics(self) -> dict:
        metrics = self.collect_system_metrics()
        
        ports = self.config.get("ports", [])
        if ports:
            metrics["port_status"] = self.check_port_status(ports)
        
        metrics["timestamp"] = datetime.utcnow().isoformat()
        return metrics
    
    def send_metrics(self, metrics: dict) -> bool:
        try:
            signed_data = self.sign_data(metrics)
            certificate = self.load_certificate()
            
            url = f"{self.server_url}/api/probe/{self.probe_key}/metrics"
            headers = {
                'X-Probe-Certificate': certificate,
                'Content-Type': 'application/json'
            }
            
            payload = {
                'probe_key': self.probe_key,
                'signed_data': signed_data
            }
            
            response = requests.post(url, json=payload, headers=headers, timeout=10)
            
            if response.status_code == 200:
                logger.info("Metrics sent successfully")
                return True
            else:
                logger.error(f"Failed to send metrics: {response.status_code}")
                return False
        except Exception as e:
            logger.error(f"Error sending metrics: {e}")
            return False
    
    def run(self):
        logger.info(f"Starting secure probe with interval {self.interval}s")
        
        while True:
            try:
                metrics = self.collect_all_metrics()
                if metrics:
                    self.send_metrics(metrics)
            except Exception as e:
                logger.error(f"Error in main loop: {e}")
            
            time.sleep(self.interval)

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", "-c", default="probe_config.json")
    parser.add_argument("--test", action="store_true")
    args = parser.parse_args()
    
    try:
        probe = SecureServerProbe(args.config)
        
        if args.test:
            print("Collecting metrics...")
            metrics = probe.collect_all_metrics()
            print(json.dumps(metrics, indent=2))
            
            print("\nSigning data...")
            signed = probe.sign_data(metrics)
            print(json.dumps(signed, indent=2))
        else:
            probe.run()
            
    except Exception as e:
        logger.error(f"Failed to start probe: {e}")
        return 1
    
    return 0

if __name__ == "__main__":
    exit(main())