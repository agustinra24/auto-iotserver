"""
Registro de sesiones a CSV - Thread-safe para múltiples workers
"""
import csv
import os
import threading
from datetime import datetime
from pathlib import Path
from typing import Optional
import logging

logger = logging.getLogger(__name__)


class SessionLogger:
    """Registro de eventos de sesión a archivo CSV"""
    
    _lock = threading.Lock()
    _csv_path = None
    
    HEADERS = [
        "timestamp", "event", "user_id", "user_type",
        "email", "jti", "ip_address", "user_agent",
        "expires_at", "reason", "endpoint"
    ]
    
    @classmethod
    def _get_csv_path(cls) -> Path:
        """Obtener ruta del archivo CSV"""
        if cls._csv_path is None:
            logs_base = Path(os.getenv("LOGS_DIR", "logs"))
            logs_dir = logs_base / "sessions"
            logs_dir.mkdir(parents=True, exist_ok=True)
            cls._csv_path = logs_dir / "sessions_history.csv"
        return cls._csv_path
    
    @classmethod
    def _ensure_headers(cls, csv_path: Path) -> None:
        """Asegurar que el CSV tiene encabezados"""
        if not csv_path.exists() or csv_path.stat().st_size == 0:
            with open(csv_path, 'w', newline='', encoding='utf-8') as f:
                writer = csv.DictWriter(f, fieldnames=cls.HEADERS)
                writer.writeheader()
    
    @classmethod
    def _write_event(cls, event_data: dict) -> None:
        """Escribir evento al CSV (thread-safe)"""
        csv_path = cls._get_csv_path()
        
        with cls._lock:
            try:
                cls._ensure_headers(csv_path)
                with open(csv_path, 'a', newline='', encoding='utf-8') as f:
                    writer = csv.DictWriter(f, fieldnames=cls.HEADERS)
                    writer.writerow(event_data)
            except Exception as e:
                logger.error(f"Error al escribir en CSV de sesiones: {e}")
    
    @classmethod
    def log_login(cls, user_id: int, user_type: str, email: str, jti: str,
                  ip: Optional[str] = None, user_agent: Optional[str] = None,
                  expires_at: Optional[str] = None) -> None:
        """Registrar inicio de sesión exitoso"""
        event_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "event": "login",
            "user_id": user_id,
            "user_type": user_type,
            "email": email or "",
            "jti": jti,
            "ip_address": ip or "",
            "user_agent": user_agent or "",
            "expires_at": expires_at or "",
            "reason": "",
            "endpoint": ""
        }
        cls._write_event(event_data)
        logger.info(f"Login registrado: {user_type} ID {user_id} desde {ip}")
    
    @classmethod
    def log_login_rejected(cls, user_id: int, user_type: str, email: str,
                           ip: Optional[str] = None, user_agent: Optional[str] = None,
                           reason: str = "session_active") -> None:
        """Registrar intento de inicio de sesión rechazado"""
        event_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "event": "login_rejected",
            "user_id": user_id,
            "user_type": user_type,
            "email": email or "",
            "jti": "",
            "ip_address": ip or "",
            "user_agent": user_agent or "",
            "expires_at": "",
            "reason": reason,
            "endpoint": ""
        }
        cls._write_event(event_data)
        logger.warning(f"Login rechazado: {user_type} ID {user_id} - {reason}")
    
    @classmethod
    def log_logout(cls, user_id: int, user_type: str, jti: str,
                   ip: Optional[str] = None, reason: str = "manual") -> None:
        """Registrar cierre de sesión"""
        event_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "event": "logout",
            "user_id": user_id,
            "user_type": user_type,
            "email": "",
            "jti": jti,
            "ip_address": ip or "",
            "user_agent": "",
            "expires_at": "",
            "reason": reason,
            "endpoint": ""
        }
        cls._write_event(event_data)
        logger.info(f"Logout registrado: {user_type} ID {user_id}")
