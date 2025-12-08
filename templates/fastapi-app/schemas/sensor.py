"""Schemas de Datos de Sensores para MongoDB"""
from pydantic import BaseModel, Field, validator
from typing import Optional, List
from datetime import datetime


class SensorReading(BaseModel):
    """Schema para recibir lecturas de sensores de dispositivos IoT"""
    device_id: int = Field(..., description="ID del dispositivo que envía las lecturas")
    temperature: Optional[float] = Field(None, description="Temperatura en Celsius")
    smoke_level: Optional[int] = Field(None, ge=0, le=100, description="Nivel de humo (0-100%)")
    battery: Optional[int] = Field(None, ge=0, le=100, description="Nivel de batería (0-100%)")
    location: Optional[str] = Field(None, max_length=200, description="Ubicación del dispositivo")
    timestamp: Optional[datetime] = Field(default_factory=datetime.utcnow)
    
    @validator('temperature')
    def validate_temperature(cls, v):
        if v is not None and (v < -50 or v > 100):
            raise ValueError('Temperatura fuera del rango válido (-50 a 100°C)')
        return v
    
    class Config:
        json_schema_extra = {
            "example": {
                "device_id": 1,
                "temperature": 25.3,
                "smoke_level": 5,
                "battery": 85,
                "location": "Main Hall",
                "timestamp": "2024-01-15T10:30:00Z"
            }
        }


class SensorReadingResponse(BaseModel):
    """Respuesta después de insertar lecturas"""
    message: str
    readings_count: int
    device_id: int
    inserted_ids: List[str]
    timestamp: datetime


class SensorReadingItem(BaseModel):
    """Elemento de lectura individual"""
    sensor_type: str
    value: float
    unit: str
    location: Optional[str]
    timestamp: datetime


class SensorReadingsHistoryResponse(BaseModel):
    """Respuesta para consultas históricas"""
    device_id: int
    readings_count: int
    readings: List[SensorReadingItem]
