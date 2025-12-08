"""User and Manager Schemas"""
from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import datetime


class UserBase(BaseModel):
    """Base user schema"""
    nombre: str
    email: EmailStr
    is_active: bool = True


class UserCreate(UserBase):
    """Schema for creating users"""
    password: str
    rol_id: int


class UserResponse(UserBase):
    """Schema for user responses"""
    id: int
    rol_id: Optional[int] = None
    created_at: datetime
    
    class Config:
        from_attributes = True


class ManagerBase(BaseModel):
    """Base manager schema"""
    nombre: str
    email: EmailStr


class ManagerCreate(ManagerBase):
    """Schema for creating managers"""
    password: str
    admin_id: int


class ManagerResponse(ManagerBase):
    """Schema for manager responses"""
    id: int
    admin_id: int
    created_at: datetime
    
    class Config:
        from_attributes = True
