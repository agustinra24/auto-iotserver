"""Device Schemas"""
from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class DeviceBase(BaseModel):
    """Base device schema"""
    nombre: str
    device_type: str
    is_active: bool = True


class DeviceCreate(DeviceBase):
    """Schema for creating devices"""
    admin_id: int


class DeviceResponse(DeviceBase):
    """Schema for device responses"""
    id: int
    admin_id: Optional[int] = None
    created_at: datetime
    
    class Config:
        from_attributes = True


class DeviceUpdate(BaseModel):
    """Schema for updating devices"""
    nombre: Optional[str] = None
    device_type: Optional[str] = None
    is_active: Optional[bool] = None
