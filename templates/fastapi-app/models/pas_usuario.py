"""User Password Table"""
from sqlalchemy import Column, Integer, String, LargeBinary
from sqlalchemy.orm import relationship
from database import Base


class PasUsuario(Base):
    __tablename__ = "pasusuario"
    
    id = Column(Integer, primary_key=True, index=True)
    hashed_password = Column(String(255), nullable=False)
    encryption_key = Column(LargeBinary(64), nullable=True)
    
    usuario = relationship("User", back_populates="pasusuario", uselist=False)
