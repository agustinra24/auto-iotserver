"""
Devices Router
Endpoints for device management
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List

from ...database import get_db
from ...api.deps import get_current_admin
from ...models.device import Device
from ...models.pasdispositivo import PasDispositivo
from ...schemas.device import DeviceCreate, DeviceResponse, DeviceUpdate
from ...core.secrets import generate_device_api_key

router = APIRouter(prefix="/devices", tags=["devices"])

@router.get("/", response_model=List[DeviceResponse])
def list_devices(
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
    current_admin = Depends(get_current_admin)
):
    """List all devices (admin only)"""
    devices = db.query(Device).offset(skip).limit(limit).all()
    return devices

@router.get("/{device_id}", response_model=DeviceResponse)
def get_device(
    device_id: int,
    db: Session = Depends(get_db),
    current_admin = Depends(get_current_admin)
):
    """Get device by ID (admin only)"""
    device = db.query(Device).filter(Device.id == device_id).first()
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    return device

@router.post("/", response_model=DeviceResponse, status_code=status.HTTP_201_CREATED)
def create_device(
    device_data: DeviceCreate,
    db: Session = Depends(get_db),
    current_admin = Depends(get_current_admin)
):
    """Create new device (admin only)"""
    # Generate API key
    api_key = generate_device_api_key()
    
    # Create device credentials
    device_creds = PasDispositivo(api_key=api_key)
    db.add(device_creds)
    db.flush()
    
    # Create device
    device = Device(
        nombre=device_data.nombre,
        device_type=device_data.device_type,
        admin_id=current_admin.id,
        pasdispositivo_id=device_creds.id
    )
    db.add(device)
    db.commit()
    db.refresh(device)
    
    return device

@router.put("/{device_id}", response_model=DeviceResponse)
def update_device(
    device_id: int,
    device_data: DeviceUpdate,
    db: Session = Depends(get_db),
    current_admin = Depends(get_current_admin)
):
    """Update device (admin only)"""
    device = db.query(Device).filter(Device.id == device_id).first()
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    
    if device_data.nombre is not None:
        device.nombre = device_data.nombre
    if device_data.is_active is not None:
        device.is_active = device_data.is_active
    
    db.commit()
    db.refresh(device)
    return device

@router.delete("/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_device(
    device_id: int,
    db: Session = Depends(get_db),
    current_admin = Depends(get_current_admin)
):
    """Delete device (admin only)"""
    device = db.query(Device).filter(Device.id == device_id).first()
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    
    db.delete(device)
    db.commit()
    return None
