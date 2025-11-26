"""Authentication Routes - 4 login types + logout"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from datetime import timedelta

from database import get_db
from core.security import (
    verify_password, create_access_token, 
    store_session, delete_session, check_existing_session
)
from core.crypto_device import DeviceCryptoPuzzle
from schemas.auth import (
    UserLogin, AdminLogin, ManagerLogin, DeviceLogin, TokenResponse
)
from models.usuario import Usuario
from models.admin import Admin
from models.manager import Manager
from models.device import Device
from models.pasusuario import PasUsuario
from models.pasadmin import PasAdmin
from models.pasgerente import PasGerente
from models.pasdispositivo import PasDispositivo
from api.deps import get_current_entity

router = APIRouter(prefix="/auth", tags=["authentication"])

@router.post("/login/user", response_model=TokenResponse)
def login_user(credentials: UserLogin, db: Session = Depends(get_db)):
    """User login with single session enforcement"""
    user = db.query(Usuario).filter(Usuario.email == credentials.email).first()
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    # Get password
    pas_user = db.query(PasUsuario).filter(PasUsuario.id == user.pasusuario_id).first()
    if not pas_user or not verify_password(credentials.password, pas_user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    # Check existing session
    if check_existing_session(user.id, "user"):
        raise HTTPException(
            status_code=409,
            detail="Ya existe una sesión activa. Debes cerrar sesión primero usando POST /logout"
        )
    
    # Create token
    token_data = {"sub": credentials.email, "id": user.id, "role": user.rol.nombre}
    access_token = create_access_token(token_data, token_type="user")
    
    # Extract JTI and store session
    from jose import jwt
    from core.config import settings
    payload = jwt.decode(access_token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    store_session(user.id, "user", payload["jti"], settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60)
    
    return TokenResponse(access_token=access_token, user_id=user.id, role=user.rol.nombre)

@router.post("/login/admin", response_model=TokenResponse)
def login_admin(credentials: AdminLogin, db: Session = Depends(get_db)):
    """Admin login with single session enforcement"""
    admin = db.query(Admin).filter(Admin.email == credentials.email).first()
    if not admin:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    pas_admin = db.query(PasAdmin).filter(PasAdmin.id == admin.pasadmin_id).first()
    if not pas_admin or not verify_password(credentials.password, pas_admin.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    if check_existing_session(admin.id, "admin"):
        raise HTTPException(status_code=409, detail="Ya existe una sesión activa")
    
    token_data = {"sub": credentials.email, "id": admin.id, "role": admin.rol.nombre}
    access_token = create_access_token(token_data, token_type="admin")
    
    from jose import jwt
    from core.config import settings
    payload = jwt.decode(access_token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    store_session(admin.id, "admin", payload["jti"], settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60)
    
    return TokenResponse(access_token=access_token, admin_id=admin.id, role=admin.rol.nombre)

@router.post("/login/manager", response_model=TokenResponse)
def login_manager(credentials: ManagerLogin, db: Session = Depends(get_db)):
    """Manager login with single session enforcement"""
    manager = db.query(Manager).filter(Manager.email == credentials.email).first()
    if not manager:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    pas_manager = db.query(PasGerente).filter(PasGerente.id == manager.pasgerente_id).first()
    if not pas_manager or not verify_password(credentials.password, pas_manager.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    if check_existing_session(manager.id, "manager"):
        raise HTTPException(status_code=409, detail="Ya existe una sesión activa")
    
    token_data = {"sub": credentials.email, "id": manager.id}
    access_token = create_access_token(token_data, token_type="manager")
    
    from jose import jwt
    from core.config import settings
    payload = jwt.decode(access_token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    store_session(manager.id, "manager", payload["jti"], settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60)
    
    return TokenResponse(access_token=access_token, manager_id=manager.id)

@router.post("/login/device", response_model=TokenResponse)
def login_device(credentials: DeviceLogin, db: Session = Depends(get_db)):
    """Device login with cryptographic puzzle verification"""
    device = db.query(Device).filter(Device.id == credentials.device_id).first()
    if not device:
        raise HTTPException(status_code=401, detail="Device not found")
    
    # Verify API key
    pas_device = db.query(PasDispositivo).filter(PasDispositivo.id == device.pasdispositivo_id).first()
    if not pas_device or pas_device.api_key != credentials.api_key:
        raise HTTPException(status_code=401, detail="Invalid API key")
    
    # Verify cryptographic puzzle
    crypto = DeviceCryptoPuzzle(db)
    result = crypto.verify_puzzle(credentials.puzzle_response)
    
    if not result.get("valido"):
        raise HTTPException(status_code=401, detail=result.get("error", "Puzzle verification failed"))
    
    if check_existing_session(device.id, "device"):
        raise HTTPException(status_code=409, detail="Ya existe una sesión activa")
    
    token_data = {"sub": f"device_{device.id}", "id": device.id}
    access_token = create_access_token(token_data, token_type="device")
    
    from jose import jwt
    from core.config import settings
    payload = jwt.decode(access_token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    store_session(device.id, "device", payload["jti"], settings.ACCESS_TOKEN_EXPIRE_MINUTES_DEVICE * 60)
    
    return TokenResponse(access_token=access_token, device_id=device.id)

@router.post("/logout", status_code=204)
def logout(entity=Depends(get_current_entity), db: Session = Depends(get_db)):
    """Logout - invalidate session"""
    entity_type = type(entity).__name__.lower()
    if entity_type == "usuario":
        entity_type = "user"
    
    delete_session(entity.id, entity_type)
    return None
