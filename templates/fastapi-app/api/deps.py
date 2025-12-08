"""Dependencias de API - Autenticación y Autorización"""
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer
from sqlalchemy.orm import Session
from typing import Union

from database import get_db
from models import User, Device, Admin, Manager, Role
from models.permission import Permission
from models.relationships import rol_permiso
from core.config import settings
from core.security import decode_token
from core.services import SessionService

security = HTTPBearer()


def get_current_user_or_device(
    credentials=Depends(security),
    db: Session = Depends(get_db)
):
    """
    Validar token JWT y verificar sesión activa en Redis.
    Retorna dict con claves 'type' y 'data'.
    """
    token = credentials.credentials
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="No se pudieron validar las credenciales",
        headers={"WWW-Authenticate": "Bearer"},
    )
    
    try:
        payload = decode_token(token)
        
        sub = payload.get("sub")
        token_type = payload.get("type")
        user_id = payload.get("id")
        jti = payload.get("jti")
        
        if not jti:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token no compatible con sistema de sesiones. Inicia sesión nuevamente."
            )
        
        # Determinar user_id para validación de sesión
        if token_type == "device":
            user_id_for_session = int(sub) if sub is not None else None
        else:
            user_id_for_session = user_id
        
        if user_id_for_session is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token inválido o incompleto",
                headers={"WWW-Authenticate": "Bearer"}
            )
        
        # Verificar sesión en Redis
        if not SessionService.verify_token_session(user_id_for_session, token_type, jti):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Sesión inválida o cerrada. Inicia sesión nuevamente.",
                headers={"WWW-Authenticate": "Bearer"}
            )
        
        # Obtener entidad según tipo
        if token_type == "user":
            user = db.query(User).filter(User.email == sub).first()
            if not user or not user.is_active:
                raise credentials_exception
            if not user.pasusuario:
                raise credentials_exception
            return {"type": "user", "data": user}
        
        elif token_type == "admin":
            admin = db.query(Admin).filter(Admin.email == sub).first()
            if not admin:
                raise credentials_exception
            if not getattr(admin, "pasadmin", None):
                raise credentials_exception
            return {"type": "admin", "data": admin}
        
        elif token_type == "manager":
            manager = db.query(Manager).filter(Manager.email == sub).first()
            if not manager:
                raise credentials_exception
            if not getattr(manager, "pasgerente", None):
                raise credentials_exception
            return {"type": "manager", "data": manager}
        
        elif token_type == "device":
            device = db.query(Device).filter(Device.id == int(sub)).first()
            if not device or not device.is_active:
                raise credentials_exception
            if not device.pasdispositivo:
                raise credentials_exception
            return {"type": "device", "data": device}
        
        else:
            raise credentials_exception
    
    except HTTPException:
        raise
    except Exception:
        raise credentials_exception


def get_current_user(credentials=Depends(security), db: Session = Depends(get_db)):
    """Obtener usuario autenticado actual"""
    result = get_current_user_or_device(credentials=credentials, db=db)
    if result["type"] != "user":
        raise HTTPException(status_code=403, detail="Solo usuarios pueden acceder")
    return result["data"]


def get_current_device(credentials=Depends(security), db: Session = Depends(get_db)):
    """Obtener dispositivo autenticado actual"""
    result = get_current_user_or_device(credentials=credentials, db=db)
    if result["type"] != "device":
        raise HTTPException(status_code=403, detail="Solo dispositivos pueden acceder")
    return result["data"]


def get_current_admin(credentials=Depends(security), db: Session = Depends(get_db)):
    """Obtener administrador autenticado actual"""
    result = get_current_user_or_device(credentials=credentials, db=db)
    if result["type"] != "admin":
        raise HTTPException(status_code=403, detail="Solo administradores pueden acceder")
    return result["data"]


def require_role(role_name: str):
    """Requerir rol específico"""
    def role_checker(current_user=Depends(get_current_user)):
        if not current_user.rol or current_user.rol.nombre != role_name:
            raise HTTPException(status_code=403, detail=f"Rol requerido: {role_name}")
        return current_user
    return role_checker


def require_permission(permission_name: str):
    """Requerir permiso específico"""
    def permission_checker(
        principal=Depends(get_current_user_or_device),
        db: Session = Depends(get_db)
    ):
        principal_type = principal["type"]
        principal_obj = principal["data"]
        
        if principal_type == "device":
            raise HTTPException(status_code=403, detail="No autorizado (los dispositivos no pueden acceder)")
        
        rol_id = getattr(principal_obj, "rol_id", None)
        if not rol_id:
            raise HTTPException(status_code=403, detail="Sin rol asignado")
        
        has_perm = (
            db.query(Permission)
            .join(rol_permiso, rol_permiso.c.permiso_id == Permission.id)
            .filter(rol_permiso.c.role_id == rol_id, Permission.name == permission_name)
            .first()
        )
        
        if not has_perm:
            raise HTTPException(status_code=403, detail=f"Permiso requerido: {permission_name}")
        
        return principal_obj
    
    return permission_checker
