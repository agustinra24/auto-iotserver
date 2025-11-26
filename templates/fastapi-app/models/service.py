"""Service Model"""
from sqlalchemy import Column, Integer, String, Text, TIMESTAMP
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base

class Service(Base):
    __tablename__ = "service"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    nombre = Column(String(100), nullable=False)
    tipo = Column(String(50), nullable=False)
    descripcion = Column(Text)
    created_at = Column(TIMESTAMP, server_default=func.now())
    
    devices = relationship("Device", secondary="servicio_dispositivo", back_populates="services")
    apps = relationship("App", secondary="servicio_app", back_populates="services")
