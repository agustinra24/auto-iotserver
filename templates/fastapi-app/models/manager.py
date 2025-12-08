"""Modelo de Gerente"""
from sqlalchemy import Column, Integer, String, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base


class Manager(Base):
    __tablename__ = "gerente"
    
    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(50), nullable=False, index=True)
    email = Column(String(100), unique=True, nullable=False, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    admin_id = Column(Integer, ForeignKey("admin.id"), nullable=True)
    pasgerente_id = Column(Integer, ForeignKey("pasgerente.id"), nullable=True)
    rol_id = Column(Integer, ForeignKey("rol.id"), nullable=True)
    
    # Relaciones
    admin = relationship("Admin", back_populates="managers")
    pasgerente = relationship("PasGerente", back_populates="gerente", uselist=False)
    rol = relationship("Role", back_populates="gerentes")
    servicios = relationship("Service", back_populates="gerente")
