"""Service-App Junction Table"""
from sqlalchemy import Column, Integer, ForeignKey
from database import Base

class ServicioApp(Base):
    __tablename__ = "servicio_app"
    
    servicio_id = Column(Integer, ForeignKey("service.id", ondelete="CASCADE"), primary_key=True)
    app_id = Column(Integer, ForeignKey("app.id", ondelete="CASCADE"), primary_key=True)
