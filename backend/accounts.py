import secrets
import database

from pyargon2 import hash


class Account:
    def __init__(self, username: str, password: str):
        self.username = username
        self.password = password
        self.current_game_id = None

def check_user_exists(username: str):
    users_collection = database.db['users']
    user = users_collection.find_one({'username': username})
    return user is not None

def register_user(username: str, password: str):
    if check_user_exists(username):
        raise ValueError("A user with that name already exists")
    users_collection = database.db['users']
    salt = secrets.token_urlsafe(16)
    hashed_password = hash(password, salt=salt)
    users_collection.insert_one({'username': username, 'password': hashed_password, 'salt': salt})

def check_valid_login(username: str, password: str) -> bool:
    users_collection = database.db['users']
    user = users_collection.find_one({'username': username})
    if user is None:
        return False
    stored_hashed_password = user['password']
    salt = user['salt']
    return hash(password, salt=salt) == stored_hashed_password

def join_game(username: str, game_id: str):
    users_collection = database.db['users']
    users_collection.update_one({'username': username}, {'$set': {'current_game_id': game_id}})

def leave_game(username: str):
    users_collection = database.db['users']
    users_collection.update_one({'username': username}, {'$set': {'current_game_id': None}})
