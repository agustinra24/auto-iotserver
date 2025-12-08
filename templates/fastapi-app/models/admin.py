"""Modelo de Administrador"""
from sqlalchemy import Column, Integer, String, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base


class Admin(Base):
    __tablename__ = "admin"
    
    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(100), nullable=False, index=True)
    email = Column(String(100), unique=True, nullable=False, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    rol_id = Column(Integer, ForeignKey("rol.id"), nullable=True)
    pasadmin_id = Column(Integer, ForeignKey("pasadmin.id"), nullable=True)
    
    # Relaciones
    rol = relationship("Role", back_populates="admins")
    pasadmin = relationship("PasAdmin", back_populates="admin", uselist=False, foreign_keys=[pasadmin_id])
    managers = relationship("Manager", back_populates="admin")
    devices = relationship("Device", back_populates="admin")
    apps = relationship("App", back_populates="admin")
