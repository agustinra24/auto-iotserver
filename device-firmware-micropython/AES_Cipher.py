import hashlib
import cryptolib
import ubinascii
import urandom

def generate_16_bytes():
    """Function to generate a random number of 16 bytes"""
    return bytes([urandom.getrandbits(8) for _ in range(16)])

def base64_encode(data_bytes):
    """Encodes bytes into a Base64 string using ubinascii"""
    return ubinascii.b2a_base64(data_bytes) # Removes trailing newline

def base64_decode(data_b64):
    """Decodes a Base64 string back into bytes using ubinascii"""
    return ubinascii.a2b_base64(data_b64)


class AESCipher:
    def __init__(self, key:bytes):
        """
        This class is to encrypt and decrypt data using the AES-128, for this reason
        the password length is 16 bytes and block structure is also 16 bytes

        :param password:
        :param iv_vector:
        """
        self.__key = key
        self.__iv_vector = generate_16_bytes()
        self.block_size = 16
        print("AES Object, the IV is:", self.__iv_vector)

    def pad(self, data:bytes ):
        """
        This function add padding to math 16 byte blocks
        :param data:
        :return: data_add_padding
        """
        pad_len = self.block_size - (len(data) % self.block_size)
        return data + bytes([pad_len] * pad_len)  # e.g. [3]*3 = [3, 3, 3]

    @staticmethod
    def unpad(data: bytes):
        """
        :param data:
        :return data without padding:
        """
        pad_len = data[-1]  # Get last byte (padding value)
        return data[:-pad_len]

    def data_encryption(self, plain_text:bytes):
        """
        This function encrypts data using AES-128
        :param plain_text:
        :return data_encrypted -> ciphertext:
        Encrypted message + IV
        """
        aes_encrypt = cryptolib.aes(self.__key, 2, self.__iv_vector)
        padded_data = self.pad(plain_text)
        cipher_text = aes_encrypt.encrypt(padded_data)
        iv_encoded = base64_encode(b'IV=' + self.__iv_vector)
        cipher_text_base64 = base64_encode(cipher_text)
        return cipher_text_base64 + iv_encoded

    def data_decryption(self, cipher_text_base64):
        #print("cipher data: ", cipher_text_base64)
        cipher_text = base64_decode(cipher_text_base64)

        iv_base64 = cipher_text_base64[-30 :] # the last 30 bytes in base 64 format is the IV vector
        self.__iv_vector = base64_decode(iv_base64)
        self.__iv_vector = self.__iv_vector[3:]
        #print("IV Vector: decrypted ", self.__iv_vector)
        cipher_text = cipher_text

        aes_decrypt = cryptolib.aes(self.__key, 2, self.__iv_vector)
        decipher_text = aes_decrypt.decrypt(cipher_text)
        decipher_text = self.unpad(decipher_text)
        return decipher_text
