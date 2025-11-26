"""Service-Device Junction Table"""
from sqlalchemy import Column, Integer, ForeignKey
from database import Base

class ServicioDispositivo(Base):
    __tablename__ = "servicio_dispositivo"
    
    dispositivo_id = Column(Integer, ForeignKey("device.id", ondelete="CASCADE"), primary_key=True)
    servicio_id = Column(Integer, ForeignKey("service.id", ondelete="CASCADE"), primary_key=True)
