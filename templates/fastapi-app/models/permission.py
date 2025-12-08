"""Permission Model"""
from sqlalchemy import Column, Integer, String
from sqlalchemy.orm import relationship
from database import Base
from models.relationships import rol_permiso


class Permission(Base):
    __tablename__ = "permiso"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), unique=True, index=True)
    description = Column(String(255), nullable=True)
    
    roles = relationship("Role", secondary=rol_permiso, back_populates="permissions")
