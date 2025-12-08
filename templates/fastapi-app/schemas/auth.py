"""Schemas de Autenticación"""
from pydantic import BaseModel, EmailStr
from typing import Optional, Dict, Any


class UserLogin(BaseModel):
    """Schema de login para usuarios, administradores y gerentes"""
    email: EmailStr
    password: str


class DeviceLogin(BaseModel):
    """Schema de login para dispositivos con puzzle criptográfico"""
    device_id: int
    api_key: str
    puzzle_response: Optional[Dict[str, Any]] = None
    
    class Config:
        json_schema_extra = {
            "example": {
                "device_id": 1,
                "api_key": "TEST_DEVICE_API_KEY_32_CHARS_XX",
                "puzzle_response": {
                    "id_origen": 1,
                    "Random dispositivo": "base64_encoded_32_bytes...",
                    "Parametro de identidad cifrado": {
                        "ciphertext": "base64_encoded_ciphertext...",
                        "iv": "base64_encoded_iv..."
                    }
                }
            }
        }


class Token(BaseModel):
    """Schema de respuesta de token"""
    access_token: str
    token_type: str = "bearer"
    user_id: Optional[int] = None
    device_id: Optional[int] = None
    admin_id: Optional[int] = None
    manager_id: Optional[int] = None
    role: Optional[str] = None
    puzzle: Optional[Dict[str, Any]] = None
