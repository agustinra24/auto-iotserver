"""Validadores reutilizables con regex"""
import re
import html


class Validators:
    """Validadores reutilizables"""
    
    @staticmethod
    def validate_email(email: str) -> bool:
        """Validar formato de email"""
        pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        return bool(re.match(pattern, email))
    
    @staticmethod
    def validate_password_strength(password: str) -> bool:
        """Validar fortaleza de contraseña"""
        if len(password) < 8:
            return False
        if not re.search(r'[A-Z]', password):
            return False
        if not re.search(r'[a-z]', password):
            return False
        if not re.search(r'\d', password):
            return False
        return True
    
    @staticmethod
    def validate_api_key(api_key: str) -> bool:
        """Validar formato de API key"""
        return len(api_key) >= 10 and api_key.isalnum()
    
    @staticmethod
    def sanitize_input(text: str, max_length: int = 255) -> str:
        """Sanitizar entrada removiendo HTML/JS"""
        text = re.sub(r'<[^>]*>', '', text)
        text = html.escape(text)
        return text[:max_length]
