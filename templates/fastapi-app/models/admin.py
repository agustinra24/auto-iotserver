"""Admin Model"""
from sqlalchemy import Column, Integer, String, ForeignKey, TIMESTAMP
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base

class Admin(Base):
    __tablename__ = "admin"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    nombre = Column(String(100), nullable=False)
    email = Column(String(100), unique=True, nullable=False)
    rol_id = Column(Integer, ForeignKey("rol.id"), nullable=False)
    pasadmin_id = Column(Integer, ForeignKey("pasadmin.id", ondelete="CASCADE"), unique=True, nullable=False)
    created_at = Column(TIMESTAMP, server_default=func.now())
    
    rol = relationship("Rol", back_populates="admins")
    managers = relationship("Manager", back_populates="admin")
    devices = relationship("Device", back_populates="admin")
    apps = relationship("App", back_populates="admin")
