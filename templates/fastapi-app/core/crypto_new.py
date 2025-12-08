"""
Gestor Criptográfico para Autenticación de Dispositivos
Autenticación basada en rompecabezas AES-256 + HMAC-SHA256
"""
import os
import hashlib
import hmac
from base64 import b64decode, b64encode
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad
from sqlalchemy.orm import Session
from core.config import settings


class CryptoManager:
    """Sistema de rompecabezas criptográfico para autenticación de dispositivos"""
    
    def __init__(self, db: Session):
        self.db = db
        # Derivar server_key de SECRET_KEY (determinístico entre workers)
        self.server_key = hashlib.sha256(
            (settings.SECRET_KEY + "|puzzle_v1").encode("utf-8")
        ).digest()
        self.server_id = os.getenv('HOSTNAME', 'server_main_001')
    
    def register_device_key(self, device_id: int, key: bytes = None) -> bytes:
        """Registrar o actualizar clave de cifrado del dispositivo"""
        from models.device import Device
        from models.pas_dispositivo import PasDispositivo
        
        try:
            if key is None:
                key = os.urandom(32)
            
            device = self.db.query(Device).filter(Device.id == device_id).first()
            if not device:
                raise ValueError(f"Dispositivo no encontrado: {device_id}")
            
            if device.pasdispositivo_id:
                pas = self.db.query(PasDispositivo).filter(
                    PasDispositivo.id == device.pasdispositivo_id
                ).first()
                if pas:
                    pas.encryption_key = key
                else:
                    raise ValueError(f"PasDispositivo {device.pasdispositivo_id} no encontrado")
            else:
                pas = PasDispositivo(encryption_key=key)
                self.db.add(pas)
                self.db.flush()
                device.pasdispositivo_id = pas.id
            
            self.db.commit()
            return key
        except Exception as e:
            self.db.rollback()
            raise ValueError(f"Error al registrar clave: {str(e)}")
    
    def get_key_by_id(self, device_id: int) -> bytes:
        """Obtener clave de cifrado del dispositivo"""
        from models.device import Device
        from models.pas_dispositivo import PasDispositivo
        
        device = self.db.query(Device).filter(Device.id == device_id).first()
        if not device or not device.pasdispositivo_id:
            return None
        
        pas = self.db.query(PasDispositivo).filter(
            PasDispositivo.id == device.pasdispositivo_id
        ).first()
        
        return pas.encryption_key if pas else None
    
    def cifrar_aes256(self, data: bytes, key: bytes) -> dict:
        """Cifrar con AES-256-CBC"""
        iv = os.urandom(16)
        cipher = AES.new(key, AES.MODE_CBC, iv)
        data_padded = pad(data, AES.block_size)
        ciphertext = cipher.encrypt(data_padded)
        return {
            'ciphertext': b64encode(ciphertext).decode('utf-8'),
            'iv': b64encode(iv).decode('utf-8')
        }
    
    def descifrar_aes256(self, encrypted_data: dict, key: bytes) -> bytes:
        """Descifrar AES-256-CBC"""
        ciphertext = b64decode(encrypted_data['ciphertext'])
        iv = b64decode(encrypted_data['iv'])
        cipher = AES.new(key, AES.MODE_CBC, iv)
        data_padded = cipher.decrypt(ciphertext)
        return unpad(data_padded, AES.block_size)
    
    def verificar_rompecabezas_dispositivo(self, rc_dispositivo_json: dict) -> dict:
        """
        Verificar rompecabezas generado por DISPOSITIVO
        
        Flujo:
        1. Dispositivo genera R2 (aleatorio)
        2. Dispositivo calcula P2 = HMAC(device_key + server_key, R2)
        3. Dispositivo cifra P2 → P2c
        4. Dispositivo envía: id_origen, Random dispositivo, Parametro de identidad cifrado
        5. Servidor reconstruye P2, descifra P2c, compara
        """
        try:
            id_origen = rc_dispositivo_json['id_origen']
            
            # Soportar ambas nomenclaturas
            if 'Random dispositivo' in rc_dispositivo_json:
                ran_dev = b64decode(rc_dispositivo_json['Random dispositivo'])
                parametro_id_cif = rc_dispositivo_json['Parametro de identidad cifrado']
            else:
                ran_dev = b64decode(rc_dispositivo_json['R2'])
                parametro_id_cif = rc_dispositivo_json['P2c']
            
            key_b = self.get_key_by_id(id_origen)
            if key_b is None:
                return {'valido': False, 'error': 'Clave de dispositivo no encontrada'}
            
            hmac_key = key_b + self.server_key
            parametro_id_reconstruida = hmac.new(hmac_key, ran_dev, hashlib.sha256).digest()
            
            try:
                parametro_id_descif = self.descifrar_aes256(parametro_id_cif, key_b)
            except Exception as e:
                return {'valido': False, 'error': f'Error de descifrado: {e}'}
            
            if parametro_id_reconstruida == parametro_id_descif:
                return {
                    'valido': True,
                    'mensaje': 'Dispositivo autenticado exitosamente',
                    'id_origen': id_origen,
                    'id_destino': self.server_id
                }
            else:
                return {'valido': False, 'error': 'Discrepancia en parámetro de identidad'}
        
        except KeyError as e:
            return {'valido': False, 'error': f'Campo faltante: {e}'}
        except Exception as e:
            return {'valido': False, 'error': f'Error de verificación: {e}'}
