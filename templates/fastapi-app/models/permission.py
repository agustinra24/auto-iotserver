"""Permission Model"""
from sqlalchemy import Column, Integer, String, Text
from sqlalchemy.orm import relationship
from database import Base

class Permission(Base):
    __tablename__ = "permission"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(100), unique=True, nullable=False)
    description = Column(Text)
    
    roles = relationship("Rol", secondary="rol_permiso", back_populates="permisos")
