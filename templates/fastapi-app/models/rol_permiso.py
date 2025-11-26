"""Role-Permission Junction Table"""
from sqlalchemy import Column, Integer, ForeignKey
from database import Base

class RolPermiso(Base):
    __tablename__ = "rol_permiso"
    
    rol_id = Column(Integer, ForeignKey("rol.id", ondelete="CASCADE"), primary_key=True)
    permiso_id = Column(Integer, ForeignKey("permission.id", ondelete="CASCADE"), primary_key=True)
