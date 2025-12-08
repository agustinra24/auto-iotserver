"""Tabla de Contraseña de Administrador"""
from sqlalchemy import Column, Integer, String, LargeBinary
from sqlalchemy.orm import relationship
from database import Base


class PasAdmin(Base):
    __tablename__ = "pasadmin"
    
    id = Column(Integer, primary_key=True, index=True)
    hashed_password = Column(String(255), nullable=False)
    encryption_key = Column(LargeBinary(64), nullable=True)
    
    admin = relationship("Admin", back_populates="pasadmin", uselist=False)
