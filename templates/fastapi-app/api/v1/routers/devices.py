"""Devices Router"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
import secrets

from database import get_db
from api.deps import require_permission
from core.utils import ResponseFormatter
from models import Device, PasDispositivo, Admin
from schemas.device import DeviceCreate, DeviceResponse

router = APIRouter(tags=["Devices"])


@router.post("/", response_model=None)
def create_device(
    payload: DeviceCreate,
    current_admin=Depends(require_permission("create_device")),
    db: Session = Depends(get_db)
):
    """
    Create an IoT device.
    
    Requires `create_device` permission.
    Creates pasdispositivo with auto-generated api_key and encryption_key.
    """
    try:
        role_name = getattr(getattr(current_admin, "rol", None), "nombre", None)
    except Exception:
        role_name = None
    
    if role_name != "admin_master":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, 
            detail="Only admin_master can create devices"
        )
    
    admin = db.query(Admin).filter(Admin.id == payload.admin_id).first()
    if not admin:
        return ResponseFormatter.error("Admin not found")
    
    # Create pasdispositivo with auto-generated api_key and encryption_key
    pas = PasDispositivo()
    pas.encryption_key = secrets.token_bytes(32)  # 32 bytes for AES-256
    db.add(pas)
    db.flush()
    
    device = Device(
        nombre=payload.nombre,
        device_type=payload.device_type,
        is_active=payload.is_active,
        admin_id=payload.admin_id,
        pasdispositivo_id=pas.id
    )
    db.add(device)
    db.commit()
    db.refresh(device)
    
    return ResponseFormatter.success(device, "Device created successfully")


@router.get("/")
def list_devices(
    current_admin=Depends(require_permission("view_reports")),
    db: Session = Depends(get_db)
):
    """List all devices"""
    devices = db.query(Device).all()
    return ResponseFormatter.success(devices, "Devices listed successfully")


@router.get("/{device_id}")
def get_device(
    device_id: int,
    current_admin=Depends(require_permission("view_reports")),
    db: Session = Depends(get_db)
):
    """Get device by ID"""
    device = db.query(Device).filter(Device.id == device_id).first()
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    return ResponseFormatter.success(device, "Device retrieved successfully")
