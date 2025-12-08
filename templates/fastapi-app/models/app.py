"""App Model"""
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base


class App(Base):
    __tablename__ = "app"
    
    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(100), nullable=False, index=True)
    version = Column(String(20), nullable=True)
    url = Column(String(255), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    admin_id = Column(Integer, ForeignKey("admin.id"), nullable=True)
    
    # Relationships
    admin = relationship("Admin", back_populates="apps")
    servicios = relationship("Service", secondary="servicio_app", back_populates="apps")
