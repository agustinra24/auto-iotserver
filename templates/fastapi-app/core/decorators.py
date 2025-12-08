"""Decoradores de validación"""
from functools import wraps
from fastapi import HTTPException, status
from core.validators import Validators
import time


def validate_email_decorator(func):
    """Validar formato de email"""
    @wraps(func)
    async def wrapper(*args, **kwargs):
        for arg_name, arg_value in kwargs.items():
            if hasattr(arg_value, 'email'):
                if not Validators.validate_email(arg_value.email):
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Formato de email inválido"
                    )
                break
        return await func(*args, **kwargs)
    return wrapper


def validate_password_decorator(func):
    """Validar fortaleza de contraseña"""
    @wraps(func)
    async def wrapper(*args, **kwargs):
        for arg_name, arg_value in kwargs.items():
            if hasattr(arg_value, 'password'):
                if not Validators.validate_password_strength(arg_value.password):
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="La contraseña debe tener al menos 8 caracteres, una mayúscula, una minúscula y un número"
                    )
                break
        return await func(*args, **kwargs)
    return wrapper


def sanitize_input_decorator(func):
    """Sanitizar entradas de texto"""
    @wraps(func)
    async def wrapper(*args, **kwargs):
        new_kwargs = {}
        for key, value in kwargs.items():
            if isinstance(value, str):
                new_kwargs[key] = Validators.sanitize_input(value)
            elif hasattr(value, '__dict__'):
                for attr_name, attr_value in value.__dict__.items():
                    if isinstance(attr_value, str):
                        setattr(value, attr_name, Validators.sanitize_input(attr_value))
                new_kwargs[key] = value
            else:
                new_kwargs[key] = value
        return await func(*args, **new_kwargs)
    return wrapper


def async_safe(func):
    """Hacer funciones síncronas compatibles con async"""
    @wraps(func)
    async def wrapper(*args, **kwargs):
        return func(*args, **kwargs)
    return wrapper


def rate_limit(max_requests: int = 100, time_window: int = 3600):
    """Decorador simple de limitación de tasa"""
    def decorator(func):
        request_times = []
        
        @wraps(func)
        async def wrapper(*args, **kwargs):
            current_time = time.time()
            request_times[:] = [t for t in request_times if current_time - t < time_window]
            
            if len(request_times) >= max_requests:
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail="Demasiadas solicitudes. Intenta de nuevo más tarde."
                )
            
            request_times.append(current_time)
            return await func(*args, **kwargs)
        return wrapper
    return decorator
