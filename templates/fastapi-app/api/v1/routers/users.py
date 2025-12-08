"""Users Router"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from database import get_db
from api.deps import get_current_user, require_permission
from schemas.user import UserCreate, UserResponse, ManagerCreate, ManagerResponse
from models import User, Role, PasUsuario, Manager, PasGerente, Admin
from core.security import get_password_hash
from core.decorators import validate_email_decorator, sanitize_input_decorator, async_safe, validate_password_decorator
from core.utils import ResponseFormatter

router = APIRouter(tags=["Users"])


@router.get("/me")
@async_safe
def read_users_me(current_user=Depends(get_current_user)):
    """Get current user profile"""
    return ResponseFormatter.success(current_user, "Profile retrieved successfully")


@router.get("/")
@async_safe
def list_users(
    current_user=Depends(require_permission("view_all_users")),
    db: Session = Depends(get_db)
):
    """List all users (requires view_all_users permission)"""
    users = db.query(User).all()
    return ResponseFormatter.success(users, "Users listed successfully")


@router.post("/")
@validate_email_decorator
@validate_password_decorator
@sanitize_input_decorator
@async_safe
def create_user(
    user: UserCreate,
    current_user=Depends(require_permission("create_user")),
    db: Session = Depends(get_db)
):
    """
    Create a new user.
    
    **Requires create_user permission.**
    
    Password is hashed with **Argon2**.
    """
    if db.query(User).filter(User.email == user.email).first():
        return ResponseFormatter.error("Email already registered")
    
    role = db.query(Role).filter(Role.id == user.rol_id).first()
    if not role:
        return ResponseFormatter.error("Role not found")
    
    hashed_password = get_password_hash(user.password)
    new_pasusuario = PasUsuario(hashed_password=hashed_password)
    db.add(new_pasusuario)
    db.flush()
    
    new_user = User(
        nombre=user.nombre,
        email=user.email,
        is_active=user.is_active,
        rol_id=user.rol_id,
        pasusuario_id=new_pasusuario.id
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    return ResponseFormatter.success(new_user, "User created successfully with Argon2")


@router.post("/manager")
@validate_email_decorator
@validate_password_decorator
@sanitize_input_decorator
@async_safe
def create_manager(
    manager: ManagerCreate,
    current_user=Depends(require_permission("create_manager")),
    db: Session = Depends(get_db)
):
    """
    Create a new manager.
    
    **Requires create_manager permission.**
    
    Password is hashed with **Argon2**.
    """
    if db.query(Manager).filter(Manager.email == manager.email).first():
        return ResponseFormatter.error("Email already registered for manager")
    
    admin = db.query(Admin).filter(Admin.id == manager.admin_id).first()
    if not admin:
        return ResponseFormatter.error("Admin not found")
    
    hashed_password = get_password_hash(manager.password)
    new_pasgerente = PasGerente(hashed_password=hashed_password)
    db.add(new_pasgerente)
    db.flush()
    
    default_manager_role = db.query(Role).filter(Role.nombre == 'manager').first()
    
    new_manager = Manager(
        nombre=manager.nombre,
        email=manager.email,
        admin_id=manager.admin_id,
        pasgerente_id=new_pasgerente.id
    )
    if default_manager_role:
        new_manager.rol_id = default_manager_role.id
    
    db.add(new_manager)
    db.commit()
    db.refresh(new_manager)
    
    return ResponseFormatter.success(new_manager, "Manager created successfully with Argon2")
