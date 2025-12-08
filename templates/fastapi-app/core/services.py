"""
Authentication and Session Services
"""
from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from datetime import timedelta
import logging

logger = logging.getLogger(__name__)


class SessionService:
    """Single session management with Redis"""
    
    @staticmethod
    def check_active_session(user_id: int, user_type: str) -> None:
        """Check if user already has active session (409 if exists)"""
        from core.config import RedisManager
        
        active_token = RedisManager.get_active_token(user_id, user_type)
        if active_token:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Active session exists for this {user_type}. "
                       f"Logout first using POST /logout"
            )
    
    @staticmethod
    def save_session(user_id: int, user_type: str, token: str, expires_in_seconds: int) -> None:
        """Save session to Redis"""
        from core.config import RedisManager
        from core.security import decode_token
        
        try:
            payload = decode_token(token)
            jti = payload.get("jti")
            
            if not jti:
                logger.error("Token generated without JTI")
                return
            
            RedisManager.save_active_token(user_id, user_type, jti, expires_in_seconds)
            logger.info(f"Session saved for {user_type} ID {user_id}")
        except Exception as e:
            logger.error(f"Error saving session to Redis: {e}")
    
    @staticmethod
    def invalidate_session(user_id: int, user_type: str, reason: str = "manual", ip: str = None) -> None:
        """Invalidate session (logout)"""
        from core.config import RedisManager
        from core.session_logger import SessionLogger
        
        jti = RedisManager.get_active_token(user_id, user_type)
        RedisManager.delete_active_token(user_id, user_type)
        logger.info(f"Session invalidated for {user_type} ID {user_id}")
        
        if jti:
            SessionLogger.log_logout(
                user_id=user_id,
                user_type=user_type,
                jti=jti,
                ip=ip,
                reason=reason
            )
    
    @staticmethod
    def verify_token_session(user_id: int, user_type: str, jti: str) -> bool:
        """Verify token JTI matches Redis session"""
        from core.config import RedisManager
        return RedisManager.is_token_valid(user_id, user_type, jti)


class AuthService:
    """Authentication services"""
    
    @staticmethod
    def auth_by_password(
        entity, 
        entity_type: str, 
        email: str, 
        password: str, 
        db: Session,
        request_ip: str = None,
        request_user_agent: str = None
    ):
        """Generic password authentication with single session enforcement"""
        from core.security import verify_password, create_access_token, extract_jti_from_token
        from core.session_logger import SessionLogger
        from datetime import datetime
        
        obj = db.query(entity).filter(entity.email == email).first()
        
        password_field_map = {
            "user": "pasusuario",
            "admin": "pasadmin",
            "manager": "pasgerente"
        }
        password_field = password_field_map.get(entity_type)
        
        if not obj or not getattr(obj, password_field, None):
            raise HTTPException(status_code=401, detail="Invalid credentials")
        
        password_obj = getattr(obj, password_field)
        if not verify_password(password, password_obj.hashed_password):
            raise HTTPException(status_code=401, detail="Invalid credentials")
        
        if hasattr(obj, 'is_active') and not obj.is_active:
            raise HTTPException(status_code=400, detail="User deactivated")
        
        # Check single session
        try:
            SessionService.check_active_session(obj.id, entity_type)
        except HTTPException as e:
            if e.status_code == status.HTTP_409_CONFLICT:
                SessionLogger.log_login_rejected(
                    user_id=obj.id,
                    user_type=entity_type,
                    email=email,
                    ip=request_ip,
                    user_agent=request_user_agent,
                    reason="session_active"
                )
            raise
        
        access_token_expires = timedelta(minutes=60)
        access_token = create_access_token(
            data={"sub": obj.email, "type": entity_type, "id": obj.id},
            expires_delta=access_token_expires
        )
        
        SessionService.save_session(obj.id, entity_type, access_token, expires_in_seconds=3600)
        
        expires_at_dt = datetime.utcnow() + access_token_expires
        SessionLogger.log_login(
            user_id=obj.id,
            user_type=entity_type,
            email=email,
            jti=extract_jti_from_token(access_token),
            ip=request_ip,
            user_agent=request_user_agent,
            expires_at=expires_at_dt.isoformat()
        )
        
        role_name = None
        if getattr(obj, "rol", None) and getattr(obj.rol, "nombre", None):
            role_name = obj.rol.nombre
        
        response = {
            "access_token": access_token,
            "token_type": "bearer",
            "role": role_name
        }
        
        if entity_type == "user":
            response["user_id"] = obj.id
        elif entity_type == "admin":
            response["admin_id"] = obj.id
        elif entity_type == "manager":
            response["manager_id"] = obj.id
        
        return response

    @staticmethod
    def auth_by_puzzle_device(
        device_id: int, 
        api_key: str, 
        puzzle_response: dict, 
        db: Session,
        request_ip: str = None,
        request_user_agent: str = None
    ):
        """Device authentication with cryptographic puzzle"""
        from core.security import create_access_token, extract_jti_from_token
        from core.crypto_new import CryptoManager
        from core.session_logger import SessionLogger
        from models import Device
        from models.pas_dispositivo import PasDispositivo
        from datetime import datetime
        
        db_device = db.query(Device).filter(Device.id == device_id).first()
        if not db_device or not db_device.pasdispositivo_id:
            raise HTTPException(status_code=401, detail="Invalid device credentials")
        
        pas_disp = db.query(PasDispositivo).filter(PasDispositivo.id == db_device.pasdispositivo_id).first()
        if not pas_disp or pas_disp.api_key != api_key:
            raise HTTPException(status_code=401, detail="Invalid device credentials")
        
        # Check single session
        try:
            SessionService.check_active_session(device_id, "device")
        except HTTPException as e:
            if e.status_code == status.HTTP_409_CONFLICT:
                SessionLogger.log_login_rejected(
                    user_id=device_id,
                    user_type="device",
                    email="",
                    ip=request_ip,
                    user_agent=request_user_agent,
                    reason="session_active"
                )
            raise
        
        if not puzzle_response:
            raise HTTPException(
                status_code=400, 
                detail="puzzle_response required. Device must generate and send cryptographic puzzle."
            )
        
        crypto_manager = CryptoManager(db)
        verification = crypto_manager.verificar_rompecabezas_dispositivo(puzzle_response)
        
        if not verification.get('valido'):
            error_msg = verification.get('error', 'Cryptographic authentication failed')
            raise HTTPException(status_code=401, detail=error_msg)
        
        access_token_expires = timedelta(minutes=1440)  # 24 hours
        access_token = create_access_token(
            data={"sub": str(db_device.id), "type": "device"},
            expires_delta=access_token_expires
        )
        
        SessionService.save_session(device_id, "device", access_token, expires_in_seconds=86400)
        
        expires_at_dt = datetime.utcnow() + access_token_expires
        SessionLogger.log_login(
            user_id=device_id,
            user_type="device",
            email="",
            jti=extract_jti_from_token(access_token),
            ip=request_ip,
            user_agent=request_user_agent,
            expires_at=expires_at_dt.isoformat()
        )
        
        return {
            "access_token": access_token,
            "token_type": "bearer",
            "device_id": db_device.id
        }
