"""
Configuración de Base de Datos
Maneja conexión MySQL con SQLAlchemy
"""
import os
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

# Obtener URL de base de datos del entorno
DATABASE_URL = os.getenv("DATABASE_URL", "mysql+pymysql://iot_user:password@mysql:3306/iot_platform")

# Crear engine
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_recycle=3600,
    pool_size=5,
    max_overflow=10
)

# Fábrica de sesiones
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Clase base para modelos
Base = declarative_base()

# Dependencia para FastAPI
def get_db():
    """Dependencia de sesión de base de datos"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
