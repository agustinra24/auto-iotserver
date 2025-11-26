"""Device Model"""
from sqlalchemy import Column, Integer, String, Boolean, Enum, ForeignKey, TIMESTAMP
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base
import enum

class DeviceType(enum.Enum):
    fire_sensor = "fire_sensor"
    smoke_detector = "smoke_detector"
    temperature_sensor = "temperature_sensor"
    humidity_sensor = "humidity_sensor"
    gas_detector = "gas_detector"
    other = "other"

class Device(Base):
    __tablename__ = "device"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    nombre = Column(String(100), nullable=False)
    device_type = Column(Enum(DeviceType), nullable=False)
    is_active = Column(Boolean, default=True)
    admin_id = Column(Integer, ForeignKey("admin.id", ondelete="CASCADE"), nullable=False)
    pasdispositivo_id = Column(Integer, ForeignKey("pasdispositivo.id", ondelete="CASCADE"), unique=True, nullable=False)
    created_at = Column(TIMESTAMP, server_default=func.now())
    last_communication = Column(TIMESTAMP, nullable=True)
    
    admin = relationship("Admin", back_populates="devices")
    services = relationship("Service", secondary="servicio_dispositivo", back_populates="devices")
