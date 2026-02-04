import os
import secrets

from pymongo import mongo_client
from pyargon2 import hash

uri = os.environ['BALLISTIC_SERV_DB_STRING']
client = mongo_client.MongoClient(uri)

def check_user_exists(username: str):
    db = client['ballistic_serv']
    users_collection = db['users']
    user = users_collection.find_one({'username': username})
    return user is not None

def register_user(username: str, password: str):
    if check_user_exists(username):
        raise ValueError("A user with that name already exists")
    db = client['ballistic_serv']
    users_collection = db['users']
    salt = secrets.token_urlsafe(16)
    hashed_password = hash(password, salt=salt)
    users_collection.insert_one({'username': username, 'password': hashed_password, 'salt': salt})

def check_valid_login(username: str, password: str):
    db = client['ballistic_serv']
    users_collection = db['users']
    user = users_collection.find_one({'username': username})
    if user is None:
        return False
    stored_hashed_password = user['password']
    salt = user['salt']
    return hash(password, salt=salt) == stored_hashed_password
