"""User Schemas"""
from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import datetime

class UserBase(BaseModel):
    email: EmailStr
    nombre: str

class UserCreate(UserBase):
    password: str
    rol_id: int = 3

class UserResponse(UserBase):
    id: int
    is_active: bool
    rol_id: int
    created_at: datetime
    
    class Config:
        from_attributes = True
