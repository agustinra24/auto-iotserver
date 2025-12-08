"""Schemas de Usuario y Gerente"""
from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import datetime


class UserBase(BaseModel):
    """Schema base de usuario"""
    nombre: str
    email: EmailStr
    is_active: bool = True


class UserCreate(UserBase):
    """Schema para crear usuarios"""
    password: str
    rol_id: int


class UserResponse(UserBase):
    """Schema para respuestas de usuario"""
    id: int
    rol_id: Optional[int] = None
    created_at: datetime
    
    class Config:
        from_attributes = True


class ManagerBase(BaseModel):
    """Schema base de gerente"""
    nombre: str
    email: EmailStr


class ManagerCreate(ManagerBase):
    """Schema para crear gerentes"""
    password: str
    admin_id: int


class ManagerResponse(ManagerBase):
    """Schema para respuestas de gerente"""
    id: int
    admin_id: int
    created_at: datetime
    
    class Config:
        from_attributes = True
