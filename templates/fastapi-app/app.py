"""
Fire Prevention Platform - Main Application
FastAPI with MongoDB for sensor data
"""
from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi
from contextlib import asynccontextmanager
from api.v1.routers import auth, users, devices, sensors, alerts
from database.mongo import MongoDBManager, create_indexes
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifecycle management"""
    # Startup
    try:
        logger.info("🚀 Starting application...")
        MongoDBManager.get_client()
        create_indexes()
        logger.info("✅ Application started successfully")
    except Exception as e:
        logger.error(f"❌ Startup error: {e}")
    
    yield
    
    # Shutdown
    try:
        logger.info("🔌 Closing connections...")
        MongoDBManager.close_connection()
        logger.info("✅ Application stopped")
    except Exception as e:
        logger.error(f"❌ Shutdown error: {e}")


app = FastAPI(
    title="Fire Prevention System API",
    description="IoT Platform with cryptographic device authentication",
    version="2.3.0",
    lifespan=lifespan
)

# Include routers
app.include_router(auth.router, prefix="/api/v1/auth")
app.include_router(users.router, prefix="/api/v1/users")
app.include_router(devices.router, prefix="/api/v1/devices")
app.include_router(sensors.router, prefix="/api/v1")
app.include_router(alerts.router, prefix="/api/v1/alerts")


def custom_openapi():
    if app.openapi_schema:
        return app.openapi_schema
    
    openapi_schema = get_openapi(
        title=app.title,
        version=app.version,
        description=app.description,
        routes=app.routes,
    )
    
    openapi_schema["components"]["securitySchemes"] = {
        "BearerAuth": {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT",
            "description": "JWT token for users, admins and managers"
        },
        "DeviceAuth": {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT",
            "description": "JWT token for IoT devices (POST /device/login)"
        }
    }
    
    no_auth_endpoints = [
        "login_user", "login_admin", "login_manager", "login_device",
        "root", "health_check", "generate_puzzle_for_testing",
        "init_device_encryption_key"
    ]
    
    device_endpoints = ["/api/v1/device/reading"]
    
    for path, path_item in openapi_schema["paths"].items():
        for operation in path_item.values():
            if isinstance(operation, dict):
                operation_id = operation.get("operationId", "")
                
                if operation_id in no_auth_endpoints:
                    continue
                
                if path in device_endpoints:
                    operation["security"] = [{"DeviceAuth": []}]
                    continue
                
                operation["security"] = [{"BearerAuth": []}]
    
    app.openapi_schema = openapi_schema
    return app.openapi_schema


app.openapi = custom_openapi


@app.get("/")
def root():
    return {"message": "Fire Prevention API v2.3", "status": "operational"}


@app.get("/health")
async def health_check():
    return {"status": "healthy"}
