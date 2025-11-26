"""API Dependencies - Authentication"""
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from typing import Union

from database import get_db
from core.security import decode_access_token, validate_session
from models.usuario import Usuario
from models.admin import Admin
from models.manager import Manager
from models.device import Device

security = HTTPBearer()

async def get_current_entity(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db)
) -> Union[Usuario, Admin, Manager, Device]:
    """Validate token and return current authenticated entity"""
    token = credentials.credentials
    
    try:
        payload = decode_access_token(token)
        entity_type = payload.get("type")
        entity_id = payload.get("id")
        jti = payload.get("jti")
        
        if not entity_type or not entity_id or not jti:
            raise HTTPException(status_code=401, detail="Invalid token")
        
        # Validate session in Redis
        if not validate_session(entity_id, entity_type, jti):
            raise HTTPException(status_code=401, detail="Session invalid or expired")
        
        # Get entity from database
        if entity_type == "user":
            entity = db.query(Usuario).filter(Usuario.id == entity_id).first()
        elif entity_type == "admin":
            entity = db.query(Admin).filter(Admin.id == entity_id).first()
        elif entity_type == "manager":
            entity = db.query(Manager).filter(Manager.id == entity_id).first()
        elif entity_type == "device":
            entity = db.query(Device).filter(Device.id == entity_id).first()
        else:
            raise HTTPException(status_code=401, detail="Unknown entity type")
        
        if not entity:
            raise HTTPException(status_code=401, detail="Entity not found")
        
        return entity
    
    except Exception as e:
        raise HTTPException(status_code=401, detail=str(e))
