"""Sensor Data Schemas for MongoDB"""
from pydantic import BaseModel, Field, validator
from typing import Optional, List
from datetime import datetime


class SensorReading(BaseModel):
    """Schema for receiving sensor readings from IoT devices"""
    device_id: int = Field(..., description="Device ID sending the readings")
    temperature: Optional[float] = Field(None, description="Temperature in Celsius")
    smoke_level: Optional[int] = Field(None, ge=0, le=100, description="Smoke level (0-100%)")
    battery: Optional[int] = Field(None, ge=0, le=100, description="Battery level (0-100%)")
    location: Optional[str] = Field(None, max_length=200, description="Device location")
    timestamp: Optional[datetime] = Field(default_factory=datetime.utcnow)
    
    @validator('temperature')
    def validate_temperature(cls, v):
        if v is not None and (v < -50 or v > 100):
            raise ValueError('Temperature out of valid range (-50 to 100°C)')
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
    """Response after inserting readings"""
    message: str
    readings_count: int
    device_id: int
    inserted_ids: List[str]
    timestamp: datetime


class SensorReadingItem(BaseModel):
    """Individual reading item"""
    sensor_type: str
    value: float
    unit: str
    location: Optional[str]
    timestamp: datetime


class SensorReadingsHistoryResponse(BaseModel):
    """Response for historical queries"""
    device_id: int
    readings_count: int
    readings: List[SensorReadingItem]
