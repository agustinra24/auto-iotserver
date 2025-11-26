"""Manager Model"""
from sqlalchemy import Column, Integer, String, ForeignKey, TIMESTAMP
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base

class Manager(Base):
    __tablename__ = "manager"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    nombre = Column(String(100), nullable=False)
    email = Column(String(100), unique=True, nullable=False)
    admin_id = Column(Integer, ForeignKey("admin.id", ondelete="CASCADE"), nullable=False)
    pasgerente_id = Column(Integer, ForeignKey("pasgerente.id", ondelete="CASCADE"), unique=True, nullable=False)
    created_at = Column(TIMESTAMP, server_default=func.now())
    
    admin = relationship("Admin", back_populates="managers")
