"""Many-to-Many relationship tables"""
from sqlalchemy import Column, Integer, ForeignKey, DateTime, Table
from datetime import datetime
from database import Base

# Role-Permission junction
rol_permiso = Table(
    "rol_permiso",
    Base.metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("role_id", Integer, ForeignKey("rol.id", ondelete="CASCADE"), nullable=False),
    Column("permiso_id", Integer, ForeignKey("permiso.id", ondelete="CASCADE"), nullable=False),
    Column("created_at", DateTime, default=datetime.utcnow)
)

# User-Service junction
usuario_servicio = Table(
    "usuario_servicio",
    Base.metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("usuario_id", Integer, ForeignKey("usuario.id"), nullable=True),
    Column("servicio_id", Integer, ForeignKey("servicio.id"), nullable=True),
    Column("gerente_id", Integer, ForeignKey("gerente.id"), nullable=True),
    Column("fecha_asignacion", DateTime, default=datetime.utcnow)
)

# Service-Device junction
servicio_dispositivo = Table(
    "servicio_dispositivo",
    Base.metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("servicio_id", Integer, ForeignKey("servicio.id"), nullable=True),
    Column("dispositivo_id", Integer, ForeignKey("dispositivo.id"), nullable=True),
    Column("admin_id", Integer, ForeignKey("admin.id"), nullable=True),
    Column("fecha_asignacion", DateTime, default=datetime.utcnow)
)

# Service-App junction
servicio_app = Table(
    "servicio_app",
    Base.metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("servicio_id", Integer, ForeignKey("servicio.id"), nullable=True),
    Column("app_id", Integer, ForeignKey("app.id"), nullable=True),
    Column("admin_id", Integer, ForeignKey("admin.id"), nullable=True),
    Column("fecha_asignacion", DateTime, default=datetime.utcnow)
)
