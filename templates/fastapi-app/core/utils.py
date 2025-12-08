"""Funciones utilitarias"""
import uuid
from datetime import datetime
from typing import Any, Dict


def generate_unique_id(prefix: str = "") -> str:
    return f"{prefix}_{uuid.uuid4().hex[:8]}" if prefix else uuid.uuid4().hex


def current_timestamp():
    return datetime.utcnow()


class ResponseFormatter:
    """Formato de respuesta consistente"""
    
    @staticmethod
    def success(data: Any = None, message: str = "Operación exitosa") -> Dict:
        return {
            "success": True,
            "message": message,
            "data": data,
            "timestamp": current_timestamp().isoformat()
        }
    
    @staticmethod
    def error(message: str = "Error en operación", details: Any = None) -> Dict:
        return {
            "success": False,
            "message": message,
            "details": details,
            "timestamp": current_timestamp().isoformat()
        }
