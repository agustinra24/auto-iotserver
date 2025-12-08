"""Authentication Routes - 4 login types + logout + testing endpoints"""
from fastapi import APIRouter, Depends, HTTPException, status, Header, Request
from sqlalchemy.orm import Session
from typing import Any, Optional

from database import get_db
from schemas.auth import UserLogin, DeviceLogin, Token
from models import User, Device, Admin, Manager
from models.pas_dispositivo import PasDispositivo
from core.decorators import (
    rate_limit,
    validate_email_decorator,
    sanitize_input_decorator,
    async_safe,
)
from core.services import AuthService, SessionService
from core.security import decode_token

router = APIRouter(tags=["Authentication"])


@router.post("/login/user", response_model=Token)
@rate_limit(max_requests=10, time_window=300)
@validate_email_decorator
@sanitize_input_decorator
@async_safe
def login_user(form_data: UserLogin, request: Request, db: Session = Depends(get_db)) -> Any:
    """
    User login - password authentication.
    
    ⚠️ SINGLE SESSION: Returns 409 Conflict if session already active.
    Must logout first using POST /logout.
    """
    return AuthService.auth_by_password(
        User, "user", 
        form_data.email, 
        form_data.password, 
        db,
        request_ip=request.client.host if request.client else None,
        request_user_agent=request.headers.get("user-agent", "")
    )


@router.post("/login/admin", response_model=Token)
@rate_limit(max_requests=10, time_window=300)
@validate_email_decorator
@sanitize_input_decorator
@async_safe
def login_admin(form_data: UserLogin, request: Request, db: Session = Depends(get_db)) -> Any:
    """
    Admin login - password authentication.
    
    ⚠️ SINGLE SESSION: Returns 409 Conflict if session already active.
    """
    return AuthService.auth_by_password(
        Admin, "admin", 
        form_data.email, 
        form_data.password, 
        db,
        request_ip=request.client.host if request.client else None,
        request_user_agent=request.headers.get("user-agent", "")
    )


@router.post("/login/manager", response_model=Token)
@rate_limit(max_requests=10, time_window=300)
@validate_email_decorator
@sanitize_input_decorator
@async_safe
def login_manager(form_data: UserLogin, request: Request, db: Session = Depends(get_db)) -> Any:
    """
    Manager login - password authentication.
    
    ⚠️ SINGLE SESSION: Returns 409 Conflict if session already active.
    """
    return AuthService.auth_by_password(
        Manager, "manager", 
        form_data.email, 
        form_data.password, 
        db,
        request_ip=request.client.host if request.client else None,
        request_user_agent=request.headers.get("user-agent", "")
    )


@router.post("/device/login", response_model=Token)
@sanitize_input_decorator
@async_safe
def login_device(device: DeviceLogin, request: Request, db: Session = Depends(get_db)) -> Any:
    """
    Device login - Cryptographic puzzle authentication.
    
    ⚠️ SINGLE SESSION: Returns 409 Conflict if session already active.
    """
    return AuthService.auth_by_puzzle_device(
        device.device_id, 
        device.api_key, 
        device.puzzle_response, 
        db,
        request_ip=request.client.host if request.client else None,
        request_user_agent=request.headers.get("user-agent", "")
    )


@router.post("/logout", status_code=204)
@async_safe
def logout(request: Request, authorization: Optional[str] = Header(None)):
    """
    Logout - Invalidate current session in Redis.
    
    Requires JWT token in Authorization: Bearer <token>
    
    Returns:
    - 204 No Content: Logout successful
    - 401 Unauthorized: Invalid or missing token
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization token required",
            headers={"WWW-Authenticate": "Bearer"}
        )
    
    token = authorization.split(" ")[1]
    
    try:
        payload = decode_token(token)
        user_id = payload.get("sub")
        user_type = payload.get("type")
        
        if not user_id or not user_type:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token"
            )
        
        # For devices, sub is the device_id
        if user_type == "device":
            user_id = int(user_id)
        else:
            # For users/admins/managers, we need the id claim
            user_id = payload.get("id")
        
        SessionService.invalidate_session(
            user_id, 
            user_type, 
            reason="manual",
            ip=request.client.host if request.client else None
        )
        
        return
    
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Logout error: {str(e)}"
        )


# =============================================================================
# TESTING ENDPOINTS - Keep for demonstrations
# =============================================================================

@router.post("/device/generate-puzzle-test", tags=["Testing"])
def generate_puzzle_for_testing(device_id: int, db: Session = Depends(get_db)):
    """
    🧪 TESTING ENDPOINT - Generate puzzle for a device.
    
    ⚠️ FOR DEVELOPMENT/TESTING ONLY
    In production, the DEVICE generates the puzzle, NOT the server.
    
    Usage in Swagger:
    1. Call this endpoint with device_id
    2. Copy the 'puzzle' object from response
    3. Use it in 'puzzle_response' field of POST /device/login
    """
    import os
    import hashlib
    import hmac
    from base64 import b64encode
    from core.crypto_new import CryptoManager
    
    db_device = db.query(Device).filter(Device.id == device_id).first()
    if not db_device:
        raise HTTPException(status_code=404, detail=f"Device with ID {device_id} not found")
    
    if not db_device.pasdispositivo_id:
        raise HTTPException(
            status_code=400, 
            detail=f"Device {device_id} has no pasdispositivo_id"
        )
    
    pas_disp = db.query(PasDispositivo).filter(PasDispositivo.id == db_device.pasdispositivo_id).first()
    
    if not pas_disp:
        raise HTTPException(
            status_code=400,
            detail=f"PasDispositivo with ID {db_device.pasdispositivo_id} not found"
        )
    
    crypto_manager = CryptoManager(db)
    
    device_key = crypto_manager.get_key_by_id(device_id)
    if not device_key:
        raise HTTPException(
            status_code=400,
            detail=f"Device {device_id} has no encryption_key. Use /device/init-encryption-key first."
        )
    
    if len(device_key) != 32:
        raise HTTPException(
            status_code=500,
            detail=f"Device encryption_key has {len(device_key)} bytes (expected: 32). "
                   f"Regenerate with POST /device/init-encryption-key?device_id={device_id}"
        )
    
    # Generate puzzle (simulating device behavior)
    ran_dev = os.urandom(32)
    hmac_key = device_key + crypto_manager.server_key
    parametro_id = hmac.new(hmac_key, ran_dev, hashlib.sha256).digest()
    parametro_id_cif = crypto_manager.cifrar_aes256(parametro_id, device_key)
    
    puzzle = {
        'id_origen': device_id,
        'Random dispositivo': b64encode(ran_dev).decode('utf-8'),
        'Parametro de identidad cifrado': parametro_id_cif
    }
    
    return {
        "message": "Puzzle generated successfully. Copy 'puzzle' object for POST /device/login",
        "device_id": device_id,
        "api_key": pas_disp.api_key,
        "puzzle": puzzle,
        "instructions": {
            "step_1": "Copy the 'puzzle' object above",
            "step_2": "Go to POST /device/login",
            "step_3": "Use this payload:",
            "payload_example": {
                "device_id": device_id,
                "api_key": pas_disp.api_key,
                "puzzle_response": "<PASTE_PUZZLE_OBJECT_HERE>"
            }
        }
    }


@router.post("/device/init-encryption-key", tags=["Testing"])
def init_device_encryption_key(device_id: int, db: Session = Depends(get_db)):
    """
    🧪 TESTING ENDPOINT - Initialize/regenerate device encryption_key.
    
    ⚠️ FOR DEVELOPMENT/TESTING ONLY
    
    Generates a new 32-byte encryption_key and saves it to DB.
    
    WARNING: This invalidates any previous puzzles generated with old key.
    """
    from core.crypto_new import CryptoManager
    
    db_device = db.query(Device).filter(Device.id == device_id).first()
    if not db_device:
        raise HTTPException(status_code=404, detail=f"Device with ID {device_id} not found")
    
    if not db_device.pasdispositivo_id:
        raise HTTPException(
            status_code=400,
            detail=f"Device {device_id} has no pasdispositivo_id"
        )
    
    pas_disp = db.query(PasDispositivo).filter(PasDispositivo.id == db_device.pasdispositivo_id).first()
    
    if not pas_disp:
        raise HTTPException(
            status_code=400,
            detail=f"PasDispositivo with ID {db_device.pasdispositivo_id} not found"
        )
    
    crypto_manager = CryptoManager(db)
    
    try:
        key = crypto_manager.register_device_key(device_id)
        
        return {
            "message": "Encryption key generated and saved successfully",
            "device_id": device_id,
            "key_length": len(key),
            "api_key": pas_disp.api_key,
            "device_info": {
                "nombre": db_device.nombre,
                "device_type": db_device.device_type,
                "pasdispositivo_id": db_device.pasdispositivo_id
            },
            "next_steps": {
                "1": "Use POST /device/generate-puzzle-test to generate a puzzle",
                "2": "Or implement puzzle generation in the real device"
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error generating key: {str(e)}")
