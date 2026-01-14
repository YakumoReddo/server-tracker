from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from datetime import datetime, timedelta
import secrets
import json
import hmac
import hashlib
from typing import Dict

class CertificateManager:
    
    def __init__(self):
        self.ca_private_key = self._generate_ca_key()
        self.ca_certificate = self._generate_ca_certificate()
    
    def _generate_ca_key(self) -> rsa.RSAPrivateKey:
        return rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048
        )
    
    def _generate_ca_certificate(self) -> x509.Certificate:
        subject = issuer = x509.Name([
            x509.NameAttribute(NameOID.COMMON_NAME, "ServerTracker CA"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "ServerTracker"),
            x509.NameAttribute(NameOID.COUNTRY_NAME, "CN"),
        ])
        
        cert = x509.CertificateBuilder().subject_name(
            subject
        ).issuer_name(
            issuer
        ).public_key(
            self.ca_private_key.public_key()
        ).serial_number(
            x509.random_serial_number()
        ).not_valid_before(
            datetime.utcnow()
        ).not_valid_after(
            datetime.utcnow() + timedelta(days=3650)
        ).add_extension(
            x509.SubjectAlternativeName([
                x509.DNSName("localhost"),
                x509.DNSName("*.servertracker.local"),
            ]),
            critical=False,
        ).sign(self.ca_private_key, hashes.SHA256())
        
        return cert
    
    def generate_probe_certificate(self, probe_info: Dict) -> Dict[str, str]:
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048
        )
        
        serial_number = secrets.token_hex(16)
        
        subject = x509.Name([
            x509.NameAttribute(NameOID.COMMON_NAME, probe_info['name']),
            x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "ServerTracker Probe"),
            x509.NameAttribute(NameOID.SERIAL_NUMBER, serial_number),
        ])
        
        cert = x509.CertificateBuilder().subject_name(
            subject
        ).issuer_name(
            self.ca_certificate.subject
        ).public_key(
            private_key.public_key()
        ).serial_number(
            int(serial_number, 16)
        ).not_valid_before(
            datetime.utcnow()
        ).not_valid_after(
            datetime.utcnow() + timedelta(days=365)
        ).add_extension(
            x509.SubjectAlternativeName([
                x509.DNSName(probe_info.get('host', 'localhost')),
                x509.IPAddress(probe_info.get('ip_address', '127.0.0.1')),
            ]),
            critical=False,
        ).sign(private_key, hashes.SHA256())
        
        certificate_pem = cert.public_bytes(serialization.Encoding.PEM).decode()
        private_key_pem = private_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption()
        ).decode()
        public_key_pem = private_key.public_key().public_bytes(
            serialization.Encoding.PEM,
            serialization.PublicFormat.SubjectPublicKeyInfo
        ).decode()
        
        return {
            'certificate': certificate_pem,
            'private_key': private_key_pem,
            'public_key': public_key_pem,
            'serial_number': serial_number
        }
    
    def verify_certificate(self, certificate_pem: str) -> bool:
        try:
            cert = x509.load_pem_x509_certificate(certificate_pem.encode())
            now = datetime.utcnow()
            if now < cert.not_valid_before or now > cert.not_valid_after:
                return False
            
            return True
        except:
            return False
    
    @property
    def ca_public_key(self):
        return self.ca_private_key.public_key()

class DataSigner:
    
    def __init__(self, private_key_pem: str):
        self.private_key_pem = private_key_pem
    
    def sign_data(self, data: Dict) -> Dict:
        sorted_data = json.dumps(data, sort_keys=True)
        
        signature = hmac.new(
            self.private_key_pem.encode(),
            sorted_data.encode(),
            hashlib.sha256
        ).hexdigest()
        
        return {
            "data": data,
            "signature": signature,
            "timestamp": datetime.utcnow().isoformat()
        }

class DataVerifier:
    
    def __init__(self, public_key_pem: str):
        self.public_key_pem = public_key_pem
    
    def verify_signature(self, signed_data: Dict) -> bool:
        try:
            data = signed_data["data"]
            signature = signed_data["signature"]
            
            sorted_data = json.dumps(data, sort_keys=True)
            
            expected_signature = hmac.new(
                self.public_key_pem.encode(),
                sorted_data.encode(),
                hashlib.sha256
            ).hexdigest()
            
            return hmac.compare_digest(signature, expected_signature)
        except:
            return False