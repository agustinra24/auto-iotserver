"""
Sensors Router - IoT Sensor Data Management
Endpoints for receiving and querying sensor readings (MongoDB)
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import Any
from datetime import datetime

from database import get_db
from api.deps import get_current_device, get_current_user
from schemas.sensor import (
    SensorReading,
    SensorReadingResponse,
    SensorReadingsHistoryResponse,
    SensorReadingItem
)
from models import Device, User
from database.mongo import get_sensor_readings_collection
import logging

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Sensors"])


@router.post("/device/reading", response_model=SensorReadingResponse, status_code=201)
def send_sensor_readings(
    reading: SensorReading,
    current_device: Device = Depends(get_current_device),
    db: Session = Depends(get_db)
) -> Any:
    """
    Endpoint for IoT devices to send sensor readings.
    
    **Authentication required:** Device JWT (POST /device/login)
    
    **Process:**
    1. Validates device_id from body matches token
    2. Normalizes readings (1 document per sensor type)
    3. Inserts into MongoDB 'sensor_readings' collection
    
    **Normalization:**
    - temperature → document type "temperature"
    - smoke_level → document type "smoke_level"
    - battery → document type "battery"
    """
    
    if reading.device_id != current_device.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Not authorized: token device_id ({current_device.id}) "
                   f"doesn't match body device_id ({reading.device_id})"
        )
    
    if reading.temperature is None and reading.smoke_level is None and reading.battery is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Must send at least one sensor reading (temperature, smoke_level or battery)"
        )
    
    timestamp = reading.timestamp or datetime.utcnow()
    
    # Normalize to individual documents
    documents = []
    
    if reading.temperature is not None:
        documents.append({
            "device_id": str(reading.device_id),
            "sensor_type": "temperature",
            "value": reading.temperature,
            "unit": "°C",
            "location": reading.location,
            "timestamp": timestamp
        })
    
    if reading.smoke_level is not None:
        documents.append({
            "device_id": str(reading.device_id),
            "sensor_type": "smoke_level",
            "value": reading.smoke_level,
            "unit": "%",
            "location": reading.location,
            "timestamp": timestamp
        })
    
    if reading.battery is not None:
        documents.append({
            "device_id": str(reading.device_id),
            "sensor_type": "battery",
            "value": reading.battery,
            "unit": "%",
            "location": reading.location,
            "timestamp": timestamp
        })
    
    try:
        collection = get_sensor_readings_collection()
        result = collection.insert_many(documents)
        
        inserted_ids = [str(oid) for oid in result.inserted_ids]
        
        logger.info(
            f"📊 Device {reading.device_id} sent {len(documents)} readings. "
            f"IDs: {inserted_ids[:3]}..."
        )
        
        return SensorReadingResponse(
            message="Readings received and saved successfully",
            readings_count=len(documents),
            device_id=reading.device_id,
            inserted_ids=inserted_ids,
            timestamp=timestamp
        )
        
    except Exception as e:
        logger.error(f"❌ Error inserting readings to MongoDB: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error saving readings: {str(e)}"
        )


@router.get("/devices/{device_id}/readings", response_model=SensorReadingsHistoryResponse)
def get_device_readings(
    device_id: int,
    sensor_type: str = None,
    start_date: datetime = None,
    end_date: datetime = None,
    limit: int = 100,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> Any:
    """
    Query device sensor readings history.
    
    **Authentication required:** User/Admin/Manager JWT
    
    **Query Parameters:**
    - sensor_type: Filter by type (temperature, smoke_level, battery)
    - start_date: Start date (ISO 8601)
    - end_date: End date (ISO 8601)
    - limit: Max records (default: 100, max: 1000)
    """
    
    device = db.query(Device).filter(Device.id == device_id).first()
    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Device with ID {device_id} not found"
        )
    
    if limit > 1000:
        limit = 1000
    
    query_filter = {"device_id": str(device_id)}
    
    if sensor_type:
        valid_types = ["temperature", "smoke_level", "battery"]
        if sensor_type not in valid_types:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"sensor_type must be one of: {', '.join(valid_types)}"
            )
        query_filter["sensor_type"] = sensor_type
    
    if start_date or end_date:
        query_filter["timestamp"] = {}
        if start_date:
            query_filter["timestamp"]["$gte"] = start_date
        if end_date:
            query_filter["timestamp"]["$lte"] = end_date
    
    try:
        collection = get_sensor_readings_collection()
        
        cursor = collection.find(query_filter).sort("timestamp", -1).limit(limit)
        
        readings = []
        for doc in cursor:
            readings.append(SensorReadingItem(
                sensor_type=doc.get("sensor_type"),
                value=doc.get("value"),
                unit=doc.get("unit"),
                location=doc.get("location"),
                timestamp=doc.get("timestamp")
            ))
        
        logger.info(
            f"📊 User {current_user.id} queried {len(readings)} readings "
            f"for device {device_id}"
        )
        
        return SensorReadingsHistoryResponse(
            device_id=device_id,
            readings_count=len(readings),
            readings=readings
        )
        
    except Exception as e:
        logger.error(f"❌ Error querying readings from MongoDB: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error querying readings: {str(e)}"
        )
