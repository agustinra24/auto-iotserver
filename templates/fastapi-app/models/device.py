"""Modelo de Dispositivo"""
from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base


class Device(Base):
    __tablename__ = "dispositivo"
    
    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(100), nullable=True, index=True)
    device_type = Column(String(50), nullable=False)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    admin_id = Column(Integer, ForeignKey("admin.id"), nullable=True)
    pasdispositivo_id = Column(Integer, ForeignKey("pasdispositivo.id"), nullable=True)
    
    # Relaciones
    admin = relationship("Admin", back_populates="devices")
    pasdispositivo = relationship(
        "PasDispositivo",
        back_populates="device",
        uselist=False,
        foreign_keys=[pasdispositivo_id]
    )
    servicios = relationship("Service", secondary="servicio_dispositivo", back_populates="dispositivos")
