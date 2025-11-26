"""Manager Password Table"""
from sqlalchemy import Column, Integer, String, LargeBinary
from database import Base

class PasGerente(Base):
    __tablename__ = "pasgerente"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    hashed_password = Column(String(255), nullable=False)
    encryption_key = Column(LargeBinary(32))
