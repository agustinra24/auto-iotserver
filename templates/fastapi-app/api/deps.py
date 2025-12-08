"""API Dependencies - Authentication and Authorization"""
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
    Validate JWT token and verify active session in Redis.
    Returns dict with 'type' and 'data' keys.
    """
    token = credentials.credentials
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
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
                detail="Token not compatible with session system. Login again."
            )
        
        # Determine user_id for session validation
        if token_type == "device":
            user_id_for_session = int(sub) if sub is not None else None
        else:
            user_id_for_session = user_id
        
        if user_id_for_session is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or incomplete token",
                headers={"WWW-Authenticate": "Bearer"}
            )
        
        # Verify session in Redis
        if not SessionService.verify_token_session(user_id_for_session, token_type, jti):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or closed session. Login again.",
                headers={"WWW-Authenticate": "Bearer"}
            )
        
        # Get entity based on type
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
    """Get current authenticated user"""
    result = get_current_user_or_device(credentials=credentials, db=db)
    if result["type"] != "user":
        raise HTTPException(status_code=403, detail="Only users can access")
    return result["data"]


def get_current_device(credentials=Depends(security), db: Session = Depends(get_db)):
    """Get current authenticated device"""
    result = get_current_user_or_device(credentials=credentials, db=db)
    if result["type"] != "device":
        raise HTTPException(status_code=403, detail="Only devices can access")
    return result["data"]


def get_current_admin(credentials=Depends(security), db: Session = Depends(get_db)):
    """Get current authenticated admin"""
    result = get_current_user_or_device(credentials=credentials, db=db)
    if result["type"] != "admin":
        raise HTTPException(status_code=403, detail="Only admins can access")
    return result["data"]


def require_role(role_name: str):
    """Require specific role"""
    def role_checker(current_user=Depends(get_current_user)):
        if not current_user.rol or current_user.rol.nombre != role_name:
            raise HTTPException(status_code=403, detail=f"Required role: {role_name}")
        return current_user
    return role_checker


def require_permission(permission_name: str):
    """Require specific permission"""
    def permission_checker(
        principal=Depends(get_current_user_or_device),
        db: Session = Depends(get_db)
    ):
        principal_type = principal["type"]
        principal_obj = principal["data"]
        
        if principal_type == "device":
            raise HTTPException(status_code=403, detail="Not authorized (devices cannot access)")
        
        rol_id = getattr(principal_obj, "rol_id", None)
        if not rol_id:
            raise HTTPException(status_code=403, detail="No role assigned")
        
        has_perm = (
            db.query(Permission)
            .join(rol_permiso, rol_permiso.c.permiso_id == Permission.id)
            .filter(rol_permiso.c.role_id == rol_id, Permission.name == permission_name)
            .first()
        )
        
        if not has_perm:
            raise HTTPException(status_code=403, detail=f"Required permission: {permission_name}")
        
        return principal_obj
    
    return permission_checker
