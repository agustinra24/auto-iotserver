"""
Configuración de MongoDB para Datos de Sensores IoT
"""
from pymongo import MongoClient
from pymongo.database import Database
from pymongo.collection import Collection
from typing import Optional
import logging
from core.config import settings

logger = logging.getLogger(__name__)


class MongoDBManager:
    """Gestor de conexión MongoDB (Singleton)"""
    
    _client: Optional[MongoClient] = None
    _database: Optional[Database] = None
    
    @classmethod
    def get_client(cls) -> MongoClient:
        """Obtener o crear cliente MongoDB"""
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
                logger.info(f"MongoDB conectado: {settings.MONGO_HOST}:{settings.MONGO_PORT}")
                
            except Exception as e:
                logger.error(f"Error de conexión MongoDB: {e}")
                raise
        
        return cls._client
    
    @classmethod
    def get_database(cls) -> Database:
        """Obtener base de datos configurada"""
        if cls._database is None:
            client = cls.get_client()
            cls._database = client[settings.MONGO_DATABASE]
            logger.info(f"Base de datos seleccionada: {settings.MONGO_DATABASE}")
        return cls._database
    
    @classmethod
    def get_collection(cls, collection_name: str) -> Collection:
        """Obtener colección específica"""
        db = cls.get_database()
        return db[collection_name]
    
    @classmethod
    def close_connection(cls) -> None:
        """Cerrar conexion MongoDB"""
        if cls._client:
            cls._client.close()
            cls._client = None
            cls._database = None
            logger.info("Conexion MongoDB cerrada")


def get_sensor_readings_collection() -> Collection:
    """Obtener colección de lecturas de sensores"""
    return MongoDBManager.get_collection("sensor_readings")


def get_device_logs_collection() -> Collection:
    """Obtener colección de logs de dispositivos"""
    return MongoDBManager.get_collection("device_logs")


def get_alerts_collection() -> Collection:
    """Obtener colección de alertas"""
    return MongoDBManager.get_collection("alerts")


def create_indexes():
    """Crear índices de MongoDB para consultas optimizadas"""
    try:
        # Índices de sensor_readings
        sensor_readings = get_sensor_readings_collection()
        sensor_readings.create_index([("device_id", 1), ("timestamp", -1)])
        sensor_readings.create_index([("sensor_type", 1)])
        sensor_readings.create_index([("timestamp", -1)])
        
        # Índices de device_logs
        device_logs = get_device_logs_collection()
        device_logs.create_index([("device_id", 1), ("timestamp", -1)])
        
        # Índices de alerts
        alerts = get_alerts_collection()
        alerts.create_index([("device_id", 1), ("resolved", 1)])
        alerts.create_index([("timestamp", -1)])
        
        logger.info("Índices de MongoDB creados exitosamente")
        
    except Exception as e:
        logger.error(f"Error al crear índices de MongoDB: {e}")
