"""Device Schemas"""
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class DeviceBase(BaseModel):
    nombre: str
    device_type: str

class DeviceCreate(DeviceBase):
    admin_id: int

class DeviceResponse(DeviceBase):
    id: int
    is_active: bool
    admin_id: int
    created_at: datetime
    last_communication: Optional[datetime] = None
    
    class Config:
        from_attributes = True
