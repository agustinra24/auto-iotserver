"""
IoT Fire Prevention Platform - Main Application
FastAPI backend with 4 authentication types
"""
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import time

from database import engine, Base
from core.config import redis_manager
from api.v1.routers import auth, users, devices

# Create database tables
Base.metadata.create_all(bind=engine)

# Initialize FastAPI app
app = FastAPI(
    title="IoT Fire Prevention Platform API",
    description="Production-grade IoT platform with cryptographic device authentication",
    version="2.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure properly in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request timing middleware
@app.middleware("http")
async def add_process_time_header(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    process_time = time.time() - start_time
    response.headers["X-Process-Time"] = str(process_time)
    return response

# Include routers
app.include_router(auth.router, prefix="/api/v1")
app.include_router(users.router, prefix="/api/v1")
app.include_router(devices.router, prefix="/api/v1")

# Root endpoint
@app.get("/")
async def root():
    return {
        "message": "IoT Fire Prevention Platform API",
        "version": "2.0",
        "status": "operational",
        "docs": "/docs"
    }

# Health check
@app.get("/health")
async def health_check():
    """Health check endpoint for Docker and monitoring"""
    try:
        # Test Redis connection
        redis_manager.connect()
        redis_status = "healthy"
    except Exception:
        redis_status = "unhealthy"
    
    return {
        "status": "healthy",
        "redis": redis_status,
        "timestamp": time.time()
    }

# Startup event
@app.on_event("startup")
async def startup_event():
    """Initialize connections on startup"""
    redis_manager.connect()
    print("✓ FastAPI application started")
    print("✓ Redis connection initialized")
    print("✓ Database tables verified")

# Shutdown event
@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    print("✓ FastAPI application shutdown")
