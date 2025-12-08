"""
MongoDB Configuration for IoT Sensor Data
"""
from pymongo import MongoClient
from pymongo.database import Database
from pymongo.collection import Collection
from typing import Optional
import logging
from core.config import settings

logger = logging.getLogger(__name__)


class MongoDBManager:
    """MongoDB connection manager (Singleton)"""
    
    _client: Optional[MongoClient] = None
    _database: Optional[Database] = None
    
    @classmethod
    def get_client(cls) -> MongoClient:
        """Get or create MongoDB client"""
        if cls._client is None:
            try:
                from urllib.parse import quote_plus
                
                username = quote_plus(settings.MONGO_USER)
                password = quote_plus(settings.MONGO_PASSWORD)
                
                mongo_uri = (
                    f"mongodb://{username}:{password}@"
                    f"{settings.MONGO_HOST}:{settings.MONGO_PORT}/"
                    f"{settings.MONGO_DATABASE}?authSource={settings.MONGO_AUTH_SOURCE}"
                )
                
                cls._client = MongoClient(
                    mongo_uri,
                    serverSelectionTimeoutMS=5000,
                    connectTimeoutMS=5000,
                    socketTimeoutMS=5000
                )
                
                cls._client.admin.command('ping')
                logger.info(f"MongoDB connected: {settings.MONGO_HOST}:{settings.MONGO_PORT}")
                
            except Exception as e:
                logger.error(f"MongoDB connection error: {e}")
                raise
        
        return cls._client
    
    @classmethod
    def get_database(cls) -> Database:
        """Get configured database"""
        if cls._database is None:
            client = cls.get_client()
            cls._database = client[settings.MONGO_DATABASE]
            logger.info(f"Database selected: {settings.MONGO_DATABASE}")
        return cls._database
    
    @classmethod
    def get_collection(cls, collection_name: str) -> Collection:
        """Get specific collection"""
        db = cls.get_database()
        return db[collection_name]
    
    @classmethod
    def close_connection(cls) -> None:
        """Close MongoDB connection"""
        if cls._client:
            cls._client.close()
            cls._client = None
            cls._database = None
            logger.info("🔌 MongoDB connection closed")


def get_sensor_readings_collection() -> Collection:
    """Get sensor readings collection"""
    return MongoDBManager.get_collection("sensor_readings")


def get_device_logs_collection() -> Collection:
    """Get device logs collection"""
    return MongoDBManager.get_collection("device_logs")


def get_alerts_collection() -> Collection:
    """Get alerts collection"""
    return MongoDBManager.get_collection("alerts")


def create_indexes():
    """Create MongoDB indexes for optimized queries"""
    try:
        # sensor_readings indexes
        sensor_readings = get_sensor_readings_collection()
        sensor_readings.create_index([("device_id", 1), ("timestamp", -1)])
        sensor_readings.create_index([("sensor_type", 1)])
        sensor_readings.create_index([("timestamp", -1)])
        
        # device_logs indexes
        device_logs = get_device_logs_collection()
        device_logs.create_index([("device_id", 1), ("timestamp", -1)])
        
        # alerts indexes
        alerts = get_alerts_collection()
        alerts.create_index([("device_id", 1), ("resolved", 1)])
        alerts.create_index([("timestamp", -1)])
        
        logger.info("MongoDB indexes created successfully")
        
    except Exception as e:
        logger.error(f"Error creating MongoDB indexes: {e}")
