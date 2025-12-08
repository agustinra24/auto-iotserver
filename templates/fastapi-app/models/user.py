"""Modelo de Usuario"""
from sqlalchemy import Column, String, Boolean, Integer, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base


class User(Base):
    __tablename__ = "usuario"
    
    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(50), nullable=False, index=True)
    email = Column(String(100), unique=True, nullable=False, index=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    rol_id = Column(Integer, ForeignKey("rol.id"), nullable=True)
    pasusuario_id = Column(Integer, ForeignKey("pasusuario.id"), nullable=True)
    
    # Relaciones
    rol = relationship("Role", back_populates="usuarios")
    pasusuario = relationship("PasUsuario", back_populates="usuario", uselist=False)
