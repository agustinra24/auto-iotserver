"""
Router de Sensores - Gestión de Datos de Sensores IoT
Endpoints para recibir y consultar lecturas de sensores (MongoDB)
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
    Endpoint para que dispositivos IoT envíen lecturas de sensores.
    
    **Autenticación requerida:** JWT de dispositivo (POST /device/login)
    
    **Proceso:**
    1. Valida que device_id del body coincida con el token
    2. Normaliza lecturas (1 documento por tipo de sensor)
    3. Inserta en colección 'sensor_readings' de MongoDB
    
    **Normalización:**
    - temperature → documento tipo "temperature"
    - smoke_level → documento tipo "smoke_level"
    - battery → documento tipo "battery"
    """
    
    if reading.device_id != current_device.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"No autorizado: device_id del token ({current_device.id}) "
                   f"no coincide con device_id del body ({reading.device_id})"
        )
    
    if reading.temperature is None and reading.smoke_level is None and reading.battery is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Debe enviar al menos una lectura de sensor (temperature, smoke_level o battery)"
        )
    
    timestamp = reading.timestamp or datetime.utcnow()
    
    # Normalizar a documentos individuales
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
            f"Dispositivo {reading.device_id} envio {len(documents)} lecturas. "
            f"IDs: {inserted_ids[:3]}..."
        )
        
        return SensorReadingResponse(
            message="Lecturas recibidas y guardadas exitosamente",
            readings_count=len(documents),
            device_id=reading.device_id,
            inserted_ids=inserted_ids,
            timestamp=timestamp
        )
        
    except Exception as e:
        logger.error(f"Error al insertar lecturas en MongoDB: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error al guardar lecturas: {str(e)}"
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
    Consultar historial de lecturas de sensores de un dispositivo.
    
    **Autenticación requerida:** JWT de Usuario/Admin/Gerente
    
    **Parámetros de consulta:**
    - sensor_type: Filtrar por tipo (temperature, smoke_level, battery)
    - start_date: Fecha de inicio (ISO 8601)
    - end_date: Fecha de fin (ISO 8601)
    - limit: Máximo de registros (default: 100, max: 1000)
    """
    
    device = db.query(Device).filter(Device.id == device_id).first()
    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Dispositivo con ID {device_id} no encontrado"
        )
    
    if limit > 1000:
        limit = 1000
    
    query_filter = {"device_id": str(device_id)}
    
    if sensor_type:
        valid_types = ["temperature", "smoke_level", "battery"]
        if sensor_type not in valid_types:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"sensor_type debe ser uno de: {', '.join(valid_types)}"
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
            f"Usuario {current_user.id} consulto {len(readings)} lecturas "
            f"para dispositivo {device_id}"
        )
        
        return SensorReadingsHistoryResponse(
            device_id=device_id,
            readings_count=len(readings),
            readings=readings
        )
        
    except Exception as e:
        logger.error(f"Error al consultar lecturas en MongoDB: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error al consultar lecturas: {str(e)}"
        )
