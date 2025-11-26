"""
Users Router
Endpoints for user management
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List

from ...database import get_db
from ...api.deps import get_current_admin
from ...models.usuario import Usuario
from ...models.pasusuario import PasUsuario
from ...schemas.user import UserCreate, UserResponse, UserUpdate
from ...core.security import hash_password

router = APIRouter(prefix="/users", tags=["users"])

@router.get("/", response_model=List[UserResponse])
def list_users(
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
    current_admin = Depends(get_current_admin)
):
    """List all users (admin only)"""
    users = db.query(Usuario).offset(skip).limit(limit).all()
    return users

@router.get("/{user_id}", response_model=UserResponse)
def get_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_admin = Depends(get_current_admin)
):
    """Get user by ID (admin only)"""
    user = db.query(Usuario).filter(Usuario.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

@router.post("/", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def create_user(
    user_data: UserCreate,
    db: Session = Depends(get_db),
    current_admin = Depends(get_current_admin)
):
    """Create new user (admin only)"""
    # Check if email exists
    if db.query(Usuario).filter(Usuario.email == user_data.email).first():
        raise HTTPException(status_code=400, detail="Email already registered")
    
    # Create password entry
    password_entry = PasUsuario(hashed_password=hash_password(user_data.password))
    db.add(password_entry)
    db.flush()
    
    # Create user
    user = Usuario(
        nombre=user_data.nombre,
        email=user_data.email,
        rol_id=user_data.rol_id,
        pasusuario_id=password_entry.id
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    
    return user

@router.put("/{user_id}", response_model=UserResponse)
def update_user(
    user_id: int,
    user_data: UserUpdate,
    db: Session = Depends(get_db),
    current_admin = Depends(get_current_admin)
):
    """Update user (admin only)"""
    user = db.query(Usuario).filter(Usuario.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    if user_data.nombre is not None:
        user.nombre = user_data.nombre
    if user_data.email is not None:
        user.email = user_data.email
    if user_data.is_active is not None:
        user.is_active = user_data.is_active
    
    db.commit()
    db.refresh(user)
    return user

@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_admin = Depends(get_current_admin)
):
    """Delete user (admin only)"""
    user = db.query(Usuario).filter(Usuario.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    db.delete(user)
    db.commit()
    return None
