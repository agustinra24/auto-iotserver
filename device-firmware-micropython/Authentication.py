## Add the authentication methods
import json
import urequests

class Authentication:
    def __init__(self, username:str, password:str, url_server:str):
        self.username = username # "username": "esp32", "password": "password123"
        self.__password = password
        self.url_server_login = url_server + "/login"
        self.url_server_protected = url_server + "/protected"
        self.token = None

    def get_jwt_token(self, ):
        login_data = json.dumps({"username": self.username, "password":self.__password}) #
        headers = {"Content-Type": "application/json"}
        response = urequests.post(f"{self.url_server_login }", data=login_data, headers=headers)

        if response.status_code == 200:
            self.token  = response.json().get("access_token")
            print("JWT Token:", self.token )
            return self.token
        else:
            print("Failed to get token:", response.text)
            return None

    def test_access_protected_resource(self):
        headers = {"Authorization": f"Bearer {self.token }"}
        print(headers)
        response = urequests.get(f"{self.url_server_protected}", headers=headers)

        if response.status_code == 200:
            print("Protected Response:", response.json())
        else:
            print("Access Denied:", response.text)
