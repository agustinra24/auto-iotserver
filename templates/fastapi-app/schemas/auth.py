"""Authentication Schemas"""
from pydantic import BaseModel, EmailStr
from typing import Optional, Dict

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class AdminLogin(BaseModel):
    email: EmailStr
    password: str

class ManagerLogin(BaseModel):
    email: EmailStr
    password: str

class DeviceLogin(BaseModel):
    device_id: int
    api_key: str
    puzzle_response: Dict

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: Optional[int] = None
    admin_id: Optional[int] = None
    manager_id: Optional[int] = None
    device_id: Optional[int] = None
    role: Optional[str] = None
