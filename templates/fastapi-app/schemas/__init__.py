"""Paquete de Schemas"""
from .auth import UserLogin, DeviceLogin, Token
from .user import UserBase, UserCreate, UserResponse, ManagerBase, ManagerCreate, ManagerResponse
from .device import DeviceBase, DeviceCreate, DeviceResponse
from .sensor import SensorReading, SensorReadingResponse, SensorReadingsHistoryResponse

__all__ = [
    "UserLogin", "DeviceLogin", "Token",
    "UserBase", "UserCreate", "UserResponse",
    "ManagerBase", "ManagerCreate", "ManagerResponse",
    "DeviceBase", "DeviceCreate", "DeviceResponse",
    "SensorReading", "SensorReadingResponse", "SensorReadingsHistoryResponse"
]
