"""
Módulo de Seguridad - JWT, Hash de Contraseñas (Argon2), Gestión de Sesiones
"""
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
import logging
import uuid
from passlib.context import CryptContext
from jose import JWTError, jwt
from fastapi import HTTPException, status
from core.config import settings

logger = logging.getLogger(__name__)

# ARGON2 - Sin límite de 72 caracteres
pwd_context = CryptContext(
    schemes=["argon2"],
    deprecated="auto",
    argon2__memory_cost=102400,
    argon2__time_cost=2,
    argon2__parallelism=8
)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verificar contraseña contra hash Argon2"""
    if hashed_password is None:
        return False
    try:
        return pwd_context.verify(plain_password, hashed_password)
    except Exception as e:
        logger.warning(f"Fallo en verificación de contraseña: {e}")
        return False


def get_password_hash(password: str) -> str:
    """Generar hash Argon2 a partir de contraseña"""
    return pwd_context.hash(password)


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Crear JWT con JTI único para seguimiento de sesión"""
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=15))
    
    jti = str(uuid.uuid4())
    
    to_encode.update({
        "exp": expire,
        "jti": jti,
        "iat": datetime.utcnow()
    })
    
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_token(token: str) -> Dict[str, Any]:
    """Decodificar y validar JWT"""
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        return payload
    except JWTError as e:
        logger.warning(f"Error al decodificar token: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token inválido o expirado",
            headers={"WWW-Authenticate": "Bearer"},
        )


def extract_jti_from_token(token: str) -> str:
    """Extraer JTI del token"""
    try:
        payload = decode_token(token)
        return payload.get("jti", "")
    except:
        return ""
