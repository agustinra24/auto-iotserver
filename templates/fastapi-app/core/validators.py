"""Reusable validators with regex"""
import re
import html


class Validators:
    """Reusable validators"""
    
    @staticmethod
    def validate_email(email: str) -> bool:
        """Validate email format"""
        pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        return bool(re.match(pattern, email))
    
    @staticmethod
    def validate_password_strength(password: str) -> bool:
        """Validate password strength"""
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
        """Validate API key format"""
        return len(api_key) >= 10 and api_key.isalnum()
    
    @staticmethod
    def sanitize_input(text: str, max_length: int = 255) -> str:
        """Sanitize input removing HTML/JS"""
        text = re.sub(r'<[^>]*>', '', text)
        text = html.escape(text)
        return text[:max_length]
