"""Rutas de Autenticación - 4 tipos de login + logout + endpoints de prueba"""
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
    Login de usuario - autenticación por contraseña.
    
    SESION UNICA: Retorna 409 Conflict si ya hay sesión activa.
    Debe cerrar sesión primero usando POST /logout.
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
    Login de administrador - autenticación por contraseña.
    
    SESION UNICA: Retorna 409 Conflict si ya hay sesión activa.
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
    Login de gerente - autenticación por contraseña.
    
    SESION UNICA: Retorna 409 Conflict si ya hay sesión activa.
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
    Login de dispositivo - Autenticación por rompecabezas criptográfico.
    
    SESION UNICA: Retorna 409 Conflict si ya hay sesión activa.
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
    Logout - Invalidar sesión actual en Redis.
    
    Requiere token JWT en Authorization: Bearer <token>
    
    Retorna:
    - 204 No Content: Logout exitoso
    - 401 Unauthorized: Token inválido o faltante
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Se requiere token de autorización",
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
                detail="Token inválido"
            )
        
        # Para dispositivos, sub es el device_id
        if user_type == "device":
            user_id = int(user_id)
        else:
            # Para usuarios/admins/managers, necesitamos el claim id
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
            detail=f"Error de logout: {str(e)}"
        )


# =============================================================================
# ENDPOINTS DE PRUEBA - Mantener para demostraciones
# =============================================================================

@router.post("/device/generate-puzzle-test", tags=["Testing"])
def generate_puzzle_for_testing(device_id: int, db: Session = Depends(get_db)):
    """
    ENDPOINT DE PRUEBA - Generar puzzle para un dispositivo.
    
    SOLO PARA DESARROLLO/PRUEBAS
    En producción, el DISPOSITIVO genera el puzzle, NO el servidor.
    
    Uso en Swagger:
    1. Llama este endpoint con device_id
    2. Copia el objeto 'puzzle' de la respuesta
    3. Úsalo en el campo 'puzzle_response' de POST /device/login
    """
    import os
    import hashlib
    import hmac
    from base64 import b64encode
    from core.crypto_new import CryptoManager
    
    db_device = db.query(Device).filter(Device.id == device_id).first()
    if not db_device:
        raise HTTPException(status_code=404, detail=f"Dispositivo con ID {device_id} no encontrado")
    
    if not db_device.pasdispositivo_id:
        raise HTTPException(
            status_code=400, 
            detail=f"Dispositivo {device_id} no tiene pasdispositivo_id"
        )
    
    pas_disp = db.query(PasDispositivo).filter(PasDispositivo.id == db_device.pasdispositivo_id).first()
    
    if not pas_disp:
        raise HTTPException(
            status_code=400,
            detail=f"PasDispositivo con ID {db_device.pasdispositivo_id} no encontrado"
        )
    
    crypto_manager = CryptoManager(db)
    
    device_key = crypto_manager.get_key_by_id(device_id)
    if not device_key:
        raise HTTPException(
            status_code=400,
            detail=f"Dispositivo {device_id} no tiene encryption_key. Usa /device/init-encryption-key primero."
        )
    
    if len(device_key) != 32:
        raise HTTPException(
            status_code=500,
            detail=f"encryption_key del dispositivo tiene {len(device_key)} bytes (esperado: 32). "
                   f"Regenera con POST /device/init-encryption-key?device_id={device_id}"
        )
    
    # Generar puzzle (simulando comportamiento del dispositivo)
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
        "message": "Puzzle generado exitosamente. Copia el objeto 'puzzle' para POST /device/login",
        "device_id": device_id,
        "api_key": pas_disp.api_key,
        "puzzle": puzzle,
        "instructions": {
            "step_1": "Copia el objeto 'puzzle' de arriba",
            "step_2": "Ve a POST /device/login",
            "step_3": "Usa este payload:",
            "payload_example": {
                "device_id": device_id,
                "api_key": pas_disp.api_key,
                "puzzle_response": "<PEGA_OBJETO_PUZZLE_AQUÍ>"
            }
        }
    }


@router.post("/device/init-encryption-key", tags=["Testing"])
def init_device_encryption_key(device_id: int, db: Session = Depends(get_db)):
    """
    ENDPOINT DE PRUEBA - Inicializar/regenerar encryption_key del dispositivo.
    
    SOLO PARA DESARROLLO/PRUEBAS
    
    Genera una nueva encryption_key de 32 bytes y la guarda en BD.
    
    ADVERTENCIA: Esto invalida cualquier puzzle previo generado con la clave anterior.
    """
    from core.crypto_new import CryptoManager
    
    db_device = db.query(Device).filter(Device.id == device_id).first()
    if not db_device:
        raise HTTPException(status_code=404, detail=f"Dispositivo con ID {device_id} no encontrado")
    
    if not db_device.pasdispositivo_id:
        raise HTTPException(
            status_code=400,
            detail=f"Dispositivo {device_id} no tiene pasdispositivo_id"
        )
    
    pas_disp = db.query(PasDispositivo).filter(PasDispositivo.id == db_device.pasdispositivo_id).first()
    
    if not pas_disp:
        raise HTTPException(
            status_code=400,
            detail=f"PasDispositivo con ID {db_device.pasdispositivo_id} no encontrado"
        )
    
    crypto_manager = CryptoManager(db)
    
    try:
        key = crypto_manager.register_device_key(device_id)
        
        return {
            "message": "Clave de cifrado generada y guardada exitosamente",
            "device_id": device_id,
            "key_length": len(key),
            "api_key": pas_disp.api_key,
            "device_info": {
                "nombre": db_device.nombre,
                "device_type": db_device.device_type,
                "pasdispositivo_id": db_device.pasdispositivo_id
            },
            "next_steps": {
                "1": "Usa POST /device/generate-puzzle-test para generar un puzzle",
                "2": "O implementa la generación de puzzle en el dispositivo real"
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error al generar clave: {str(e)}")
