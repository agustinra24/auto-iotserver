"""Service Model"""
from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey, Enum
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base


class Service(Base):
    __tablename__ = "servicio"
    
    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(100), nullable=False, index=True)
    descripcion = Column(Text, nullable=True)
    fecha_inicio = Column(DateTime, nullable=False)
    fecha_fin = Column(DateTime, nullable=True)
    estado = Column(Enum('conectado', 'desconectado', name='estado_servicio'), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    gerente_id = Column(Integer, ForeignKey("gerente.id"), nullable=True)
    
    # Relationships
    gerente = relationship("Manager", back_populates="servicios")
    dispositivos = relationship("Device", secondary="servicio_dispositivo", back_populates="servicios")
    apps = relationship("App", secondary="servicio_app", back_populates="servicios")
