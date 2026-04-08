import json
import urequests

class Authentication2:
    def __init__(self, username, password, login_url):
        self.username = username
        self.__password = password
        self.login_url = login_url
        self.token = None

    def get_session_token(self):
        credentials = {
            "username": self.username,
            "password": self.__password
        }
        res = urequests.post(self.login_url, json=credentials)
        self.token = res.json().get("token")
        res.close()
        if not self.token:
            print("Login failed")
        return self.token

