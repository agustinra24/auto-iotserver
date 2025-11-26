"""
Configuration Settings
Handles environment variables and Redis connection
"""
import os
from pydantic_settings import BaseSettings
import redis
from typing import Optional

class Settings(BaseSettings):
    # Database
    DATABASE_URL: str = os.getenv("DATABASE_URL", "mysql+pymysql://iot_user:password@mysql:3306/iot_platform")
    
    # Redis
    REDIS_HOST: str = os.getenv("REDIS_HOST", "redis")
    REDIS_PORT: int = int(os.getenv("REDIS_PORT", 6379))
    REDIS_PASSWORD: str = os.getenv("REDIS_PASSWORD", "")
    
    # JWT
    SECRET_KEY: str = os.getenv("SECRET_KEY", "")
    ALGORITHM: str = os.getenv("ALGORITHM", "HS256")
    ACCESS_TOKEN_EXPIRE_MINUTES: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", 60))
    ACCESS_TOKEN_EXPIRE_MINUTES_DEVICE: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES_DEVICE", 1440))
    
    class Config:
        case_sensitive = True

settings = Settings()

class RedisManager:
    """Redis connection manager for session management"""
    def __init__(self):
        self.client: Optional[redis.Redis] = None
    
    def connect(self):
        """Establish Redis connection"""
        if not self.client:
            self.client = redis.Redis(
                host=settings.REDIS_HOST,
                port=settings.REDIS_PORT,
                password=settings.REDIS_PASSWORD,
                decode_responses=True,
                socket_connect_timeout=5
            )
    
    def get_session(self, key: str) -> Optional[str]:
        """Retrieve session JTI from Redis"""
        if not self.client:
            self.connect()
        return self.client.get(key)
    
    def set_session(self, key: str, value: str, ttl: int):
        """Store session JTI in Redis with TTL"""
        if not self.client:
            self.connect()
        self.client.setex(key, ttl, value)
    
    def delete_session(self, key: str):
        """Remove session from Redis"""
        if not self.client:
            self.connect()
        self.client.delete(key)

redis_manager = RedisManager()
