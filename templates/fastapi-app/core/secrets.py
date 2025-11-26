"""
Secrets Utilities
Helper functions for generating secure random values
"""
import secrets
import string

def generate_device_api_key(length: int = 32) -> str:
    """
    Generate secure random API key for device authentication
    
    Args:
        length: Length of API key (default 32)
    
    Returns:
        str: URL-safe random string
    """
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))

def generate_encryption_key() -> bytes:
    """Generate 32-byte encryption key"""
    return secrets.token_bytes(32)
