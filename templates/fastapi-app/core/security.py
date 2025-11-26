"""
Security Module - JWT, Password Hashing, Session Management
"""
from datetime import datetime, timedelta
from typing import Optional, Dict
from jose import JWTError, jwt
from passlib.context import CryptContext
from .config import settings, redis_manager
import uuid

# Password hashing context (bcrypt)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify password against bcrypt hash"""
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password: str) -> str:
    """Generate bcrypt hash from password"""
    return pwd_context.hash(password)

def create_access_token(data: dict, token_type: str = "user", expires_delta: Optional[timedelta] = None) -> str:
    """
    Create JWT access token with JTI for session tracking
    
    Args:
        data: Payload data (must include 'sub' and 'id')
        token_type: Type of token (user, admin, manager, device)
        expires_delta: Custom expiration time
    
    Returns:
        Encoded JWT token
    """
    to_encode = data.copy()
    
    # Generate unique JTI for session tracking
    jti = str(uuid.uuid4())
    to_encode.update({"jti": jti})
    
    # Set expiration
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        # Default expiration based on type
        if token_type == "device":
            minutes = settings.ACCESS_TOKEN_EXPIRE_MINUTES_DEVICE
        else:
            minutes = settings.ACCESS_TOKEN_EXPIRE_MINUTES
        expire = datetime.utcnow() + timedelta(minutes=minutes)
    
    to_encode.update({
        "exp": expire,
        "iat": datetime.utcnow(),
        "type": token_type
    })
    
    # Encode token
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return encoded_jwt

def decode_access_token(token: str) -> Dict:
    """
    Decode and validate JWT token
    
    Args:
        token: JWT token string
    
    Returns:
        Decoded payload
    
    Raises:
        JWTError: If token is invalid or expired
    """
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        return payload
    except JWTError:
        raise

def store_session(entity_id: int, entity_type: str, jti: str, ttl: int):
    """
    Store session in Redis for single-session enforcement
    
    Args:
        entity_id: User/Admin/Manager/Device ID
        entity_type: Type (user, admin, manager, device)
        jti: JWT ID from token
        ttl: Time to live in seconds
    """
    key = f"session:{entity_type}:{entity_id}"
    redis_manager.set_session(key, jti, ttl)

def validate_session(entity_id: int, entity_type: str, jti: str) -> bool:
    """
    Validate that session JTI matches stored JTI in Redis
    
    Args:
        entity_id: Entity ID
        entity_type: Type of entity
        jti: JTI from token
    
    Returns:
        True if session is valid, False otherwise
    """
    key = f"session:{entity_type}:{entity_id}"
    stored_jti = redis_manager.get_session(key)
    return stored_jti == jti

def delete_session(entity_id: int, entity_type: str):
    """
    Delete session from Redis (logout)
    
    Args:
        entity_id: Entity ID
        entity_type: Type of entity
    """
    key = f"session:{entity_type}:{entity_id}"
    redis_manager.delete_session(key)

def check_existing_session(entity_id: int, entity_type: str) -> bool:
    """
    Check if active session exists for entity
    
    Args:
        entity_id: Entity ID
        entity_type: Type of entity
    
    Returns:
        True if session exists, False otherwise
    """
    key = f"session:{entity_type}:{entity_id}"
    return redis_manager.get_session(key) is not None
