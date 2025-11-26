"""App Model"""
from sqlalchemy import Column, Integer, String, ForeignKey, TIMESTAMP
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base

class App(Base):
    __tablename__ = "app"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    nombre = Column(String(100), nullable=False)
    version = Column(String(20), nullable=False)
    admin_id = Column(Integer, ForeignKey("admin.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(TIMESTAMP, server_default=func.now())
    
    admin = relationship("Admin", back_populates="apps")
    services = relationship("Service", secondary="servicio_app", back_populates="apps")
