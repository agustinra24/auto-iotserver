import json
import urequests
import urandom
import hashlib

def generate_salt(length=16):
    """
    Generate a random salt of given length.
    """
    return bytes([urandom.getrandbits(8) for _ in range(length)])

def hash_password_with_salt(password:str):
    """
    Hash a password with a random salt using SHA-256 in MicroPython.
    """
    salt = generate_salt()
    print(f"the  salt is: {salt.hex()} ")
    password_hash = hashlib.sha256(password.encode()).digest().hex()
    salted_password = salt.hex() + password_hash
    salted_password_hashed = hashlib.sha256(salted_password.encode()).digest()
    print(f"the  password hash with salt is: {salted_password_hashed.hex()} ")

    return salt.hex(), salted_password_hashed.hex()


class Authentication3:
    def __init__(self, username, password, login_url):
        """
        Authentication Class to get a session ID for IoT Device

        :param username:
        :param password:
        :param login_url:
        """
        self.username = username
        self.__password = password
        self.login_url = login_url
        self.token = None
        self.cookies = {}
        self.salt = None

    def get_session_token(self):
        login_headers = {
            'Content-Type': 'application/json'
        }
        # generate hashed password
        self.salt, password = hash_password_with_salt(self.__password)

        login_payload = {
            "username": self.username,
            "password": password,
            "salt": self.salt
        }
        response = urequests.post(self.login_url, headers=login_headers, data=json.dumps(login_payload))
        print(response.headers)

        if 'Set-Cookie' in response.headers:
            cookie_value = response.headers['Set-Cookie']
            cookie_parts = cookie_value.split(';')[0].split('=')
            if len(cookie_parts) == 2:
                self.cookies[cookie_parts[0]] = cookie_parts[1]
            print("Returned Cookies:", self.cookies)
        else:
            print("Not cookie received")

        response.close()
        #sleep(3)
        cookie_header = '; '.join([f"{key}={value}" for key, value in self.cookies.items()])

        return cookie_header