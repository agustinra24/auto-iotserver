"""Device Password/API Key Table"""
from sqlalchemy import Column, Integer, String, LargeBinary
from database import Base

class PasDispositivo(Base):
    __tablename__ = "pasdispositivo"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    api_key = Column(String(255), unique=True, nullable=False)
    encryption_key = Column(LargeBinary(32))
