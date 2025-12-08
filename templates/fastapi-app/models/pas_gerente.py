"""Manager Password Table"""
from sqlalchemy import Column, Integer, String, LargeBinary
from sqlalchemy.orm import relationship
from database import Base


class PasGerente(Base):
    __tablename__ = "pasgerente"
    
    id = Column(Integer, primary_key=True, index=True)
    hashed_password = Column(String(255), nullable=False)
    encryption_key = Column(LargeBinary(64), nullable=True)
    
    gerente = relationship("Manager", back_populates="pasgerente", uselist=False)
