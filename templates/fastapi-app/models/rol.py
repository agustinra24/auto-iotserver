"""Role Model"""
from sqlalchemy import Column, Integer, String, Text
from sqlalchemy.orm import relationship
from database import Base

class Rol(Base):
    __tablename__ = "rol"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    nombre = Column(String(50), unique=True, nullable=False)
    descripcion = Column(Text)
    
    # Relationships
    admins = relationship("Admin", back_populates="rol")
    usuarios = relationship("Usuario", back_populates="rol")
    permisos = relationship("Permission", secondary="rol_permiso", back_populates="roles")
