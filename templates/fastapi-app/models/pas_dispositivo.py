"""Tabla de API Key / Clave de Cifrado de Dispositivo"""
from sqlalchemy import Column, Integer, String, LargeBinary
from sqlalchemy.orm import relationship
import secrets
import string
from database import Base


class PasDispositivo(Base):
    __tablename__ = "pasdispositivo"
    
    id = Column(Integer, primary_key=True, index=True)
    api_key = Column(String(255), unique=True, index=True, nullable=False)
    encryption_key = Column(LargeBinary(64), nullable=True)
    
    device = relationship("Device", back_populates="pasdispositivo", uselist=False)
    
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        if not self.api_key:
            # Auto-generar API key si no se proporciona
            alphabet = string.ascii_letters + string.digits
            self.api_key = ''.join(secrets.choice(alphabet) for _ in range(32))
