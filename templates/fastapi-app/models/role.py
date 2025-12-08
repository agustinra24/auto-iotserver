"""Modelo de Rol"""
from sqlalchemy import Column, Integer, String
from sqlalchemy.orm import relationship
from database import Base
from models.relationships import rol_permiso


class Role(Base):
    __tablename__ = "rol"
    
    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(50), unique=True, nullable=False)
    description = Column(String(255), nullable=True)
    
    # Relaciones
    permissions = relationship(
        "Permission",
        secondary=rol_permiso,
        back_populates="roles"
    )
    usuarios = relationship("User", back_populates="rol")
    admins = relationship("Admin", back_populates="rol")
    gerentes = relationship("Manager", back_populates="rol")
