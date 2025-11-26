"""
Cryptographic Device Authentication Module
Implements zero-knowledge proof-like mechanism for device authentication
"""
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad
from Crypto.Random import get_random_bytes
import hmac
import hashlib
from base64 import b64encode, b64decode
from typing import Dict
from .config import settings

class DeviceCryptoPuzzle:
    """
    Cryptographic puzzle system for device authentication
    
    Mathematical foundation:
    K_HMAC = K_device || K_server
    P2 = HMAC-SHA256(K_HMAC, R2)
    P2c = AES-256-CBC(P2, K_device)
    
    Device proves knowledge of K_device without transmitting it
    """
    
    def __init__(self, db_session):
        self.db = db_session
        # Derive server key from SECRET_KEY
        self.server_key = hashlib.sha256(
            (settings.SECRET_KEY + "puzzle_v1").encode()
        ).digest()
    
    def get_device_encryption_key(self, device_id: int) -> bytes:
        """
        Retrieve device's 32-byte encryption key from database
        
        Args:
            device_id: Device ID
        
        Returns:
            32-byte encryption key
        """
        from models.pasdispositivo import PasDispositivo
        from models.device import Device
        from sqlalchemy import select
        
        # Get device password entry
        stmt = select(Device).where(Device.id == device_id)
        device = self.db.execute(stmt).scalar_one_or_none()
        
        if not device:
            raise ValueError(f"Device {device_id} not found")
        
        # Get encryption key
        stmt = select(PasDispositivo).where(PasDispositivo.id == device.pasdispositivo_id)
        pas_device = self.db.execute(stmt).scalar_one_or_none()
        
        if not pas_device or not pas_device.encryption_key:
            raise ValueError(f"Encryption key not found for device {device_id}")
        
        return pas_device.encryption_key
    
    def verify_puzzle(self, puzzle_response: Dict) -> Dict:
        """
        Verify cryptographic puzzle response from device
        
        Args:
            puzzle_response: Dictionary containing:
                - id_origen: Device ID
                - Random dispositivo: Base64 encoded R2 (32 bytes)
                - Parametro de identidad cifrado: {ciphertext, iv}
        
        Returns:
            Dictionary with validation result
        """
        try:
            device_id = puzzle_response["id_origen"]
            R2 = b64decode(puzzle_response["Random dispositivo"])
            P2c_data = puzzle_response["Parametro de identidad cifrado"]
            P2c_bytes = b64decode(P2c_data["ciphertext"])
            iv = b64decode(P2c_data["iv"])
            
            # Get device encryption key from database
            key_device = self.get_device_encryption_key(device_id)
            
            # Reconstruct expected P2
            hmac_key = key_device + self.server_key
            P2_expected = hmac.new(hmac_key, R2, hashlib.sha256).digest()
            
            # Decrypt received P2c
            cipher = AES.new(key_device, AES.MODE_CBC, iv)
            P2_decrypted = unpad(cipher.decrypt(P2c_bytes), AES.block_size)
            
            # Compare
            if P2_expected == P2_decrypted:
                return {
                    "valido": True,
                    "mensaje": "Device authenticated successfully",
                    "device_id": device_id
                }
            else:
                return {
                    "valido": False,
                    "error": "Parameter mismatch - authentication failed"
                }
        
        except Exception as e:
            return {
                "valido": False,
                "error": f"Puzzle verification error: {str(e)}"
            }
    
    def generate_puzzle_for_device(self, device_id: int) -> Dict:
        """
        Generate puzzle for device (simulation for testing)
        
        In production, device generates this locally.
        This method is for testing purposes only.
        
        Args:
            device_id: Device ID
        
        Returns:
            Puzzle response dictionary
        """
        # Get device key
        key_device = self.get_device_encryption_key(device_id)
        
        # 1. Generate random challenge
        R2 = get_random_bytes(32)
        
        # 2. Calculate HMAC
        hmac_key = key_device + self.server_key
        P2 = hmac.new(hmac_key, R2, hashlib.sha256).digest()
        
        # 3. Encrypt P2
        cipher = AES.new(key_device, AES.MODE_CBC)
        P2c = cipher.encrypt(pad(P2, AES.block_size))
        
        # 4. Build puzzle response
        puzzle = {
            "id_origen": device_id,
            "Random dispositivo": b64encode(R2).decode(),
            "Parametro de identidad cifrado": {
                "ciphertext": b64encode(P2c).decode(),
                "iv": b64encode(cipher.iv).decode()
            }
        }
        
        return puzzle
    
    def initialize_device_key(self, device_id: int) -> bytes:
        """
        Initialize encryption key for new device
        
        Args:
            device_id: Device ID
        
        Returns:
            Generated 32-byte encryption key
        """
        from models.pasdispositivo import PasDispositivo
        from models.device import Device
        from sqlalchemy import select
        
        # Generate new key
        encryption_key = get_random_bytes(32)
        
        # Get device
        stmt = select(Device).where(Device.id == device_id)
        device = self.db.execute(stmt).scalar_one_or_none()
        
        if not device:
            raise ValueError(f"Device {device_id} not found")
        
        # Update password entry
        stmt = select(PasDispositivo).where(PasDispositivo.id == device.pasdispositivo_id)
        pas_device = self.db.execute(stmt).scalar_one_or_none()
        
        if pas_device:
            pas_device.encryption_key = encryption_key
            self.db.commit()
        
        return encryption_key
