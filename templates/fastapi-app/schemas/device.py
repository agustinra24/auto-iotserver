"""Schemas de Dispositivo"""
from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class DeviceBase(BaseModel):
    """Schema base de dispositivo"""
    nombre: str
    device_type: str
    is_active: bool = True


class DeviceCreate(DeviceBase):
    """Schema para crear dispositivos"""
    admin_id: int


class DeviceResponse(DeviceBase):
    """Schema para respuestas de dispositivo"""
    id: int
    admin_id: Optional[int] = None
    created_at: datetime
    
    class Config:
        from_attributes = True


class DeviceUpdate(BaseModel):
    """Schema para actualizar dispositivos"""
    nombre: Optional[str] = None
    device_type: Optional[str] = None
    is_active: Optional[bool] = None
