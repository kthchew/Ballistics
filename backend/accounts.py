import secrets
from datetime import datetime
from enum import Enum

from bson import ObjectId

import database

from pyargon2 import hash


class Account:
    def __init__(self, username: str, password: str):
        self.username = username
        self.password = password
        self.current_game_id = None
        self.friends = []
        self.friend_requests = []


class FriendRequest:
    # the "to user" is the user in which this request appears in the `friend_requests` field
    def __init__(self, from_user: ObjectId, date: str):
        self.from_user = from_user
        self.date = date

def username_to_id(username: str) -> ObjectId | None:
    users_collection = database.db['users']
    user = users_collection.find_one({'username': username})
    if user is None:
        return None
    return user['_id']

def id_to_username(user_id: ObjectId) -> str | None:
    users_collection = database.db['users']
    user = users_collection.find_one({'_id': user_id})
    if user is None:
        return None
    return user['username']

def check_user_exists(username: str) -> bool:
    users_collection = database.db['users']
    user = users_collection.find_one({'username': username})
    return user is not None

def register_user(username: str, password: str) -> bool:
    if check_user_exists(username):
        raise ValueError("A user with that name already exists")
    users_collection = database.db['users']
    salt = secrets.token_urlsafe(16)
    hashed_password = hash(password, salt=salt)
    result = users_collection.insert_one({
        'username': username,
        'password': hashed_password,
        'salt': salt,
        'current_game_id': None,
        'friends': [],
        'friend_requests': [],
        'game_invites': []
    })
    return result.acknowledged

def check_valid_login(username: str, password: str) -> bool:
    users_collection = database.db['users']
    user = users_collection.find_one({'username': username})
    if user is None:
        return False
    stored_hashed_password = user['password']
    salt = user['salt']
    return hash(password, salt=salt) == stored_hashed_password

def join_game(username: str, game_id: str) -> bool:
    users_collection = database.db['users']
    games_collection = database.db['games']
    if games_collection.find_one({'game_id': game_id}) is None:
        return False
    result = users_collection.update_one({'username': username}, {'$set': {'current_game_id': game_id}})
    return result.modified_count > 0

def leave_game(username: str) -> bool:
    users_collection = database.db['users']
    result = users_collection.update_one({'username': username}, {'$set': {'current_game_id': None}})
    return result.modified_count > 0

def list_friends_ids(user_id: ObjectId) -> list:
    users_collection = database.db['users']
    user = users_collection.find_one({'_id': user_id})
    if user is None:
        return []
    return user.get('friends', [])

def list_friend_requests(user_id: ObjectId) -> list:
    users_collection = database.db['users']
    user = users_collection.find_one({'_id': user_id})
    if user is None:
        return []
    return user.get('friend_requests', [])

def list_game_invites(user_id: ObjectId) -> list:
    users_collection = database.db['users']
    user = users_collection.find_one({'_id': user_id})
    if user is None:
        return []
    return user.get('game_invites', [])

def send_friend_request(from_user_id: ObjectId, to_user_name: str) -> bool:
    users_collection = database.db['users']
    from_user = users_collection.find_one({'_id': from_user_id})
    if from_user is None or from_user['username'] == to_user_name:
        return False
    existing_req = users_collection.find_one({'username': to_user_name, 'friend_requests.from_user': from_user_id})
    if existing_req is not None:
        return False
    existing_friend = users_collection.find_one({'username': to_user_name, 'friends': from_user_id})
    if existing_friend is not None:
        return False
    friend_request = FriendRequest(from_user['_id'], date=datetime.now().isoformat())
    result = users_collection.update_one({'username': to_user_name}, {'$push': {'friend_requests': friend_request.__dict__}})
    return result.modified_count > 0

def send_game_invite(from_user_id: ObjectId, to_user_name: str, room_code: str) -> bool:
    users_collection = database.db['users']
    from_user = users_collection.find_one({'_id': from_user_id})
    if from_user is None or from_user['username'] == to_user_name:
        return False

    to_user = users_collection.find_one({'username': to_user_name})
    if to_user is None:
        return False

    # Only friends can send game invites.
    if from_user_id not in to_user.get('friends', []):
        return False

    normalized_room_code = room_code.strip().upper()
    if normalized_room_code == '':
        return False

    duplicate_invite = users_collection.find_one({
        '_id': to_user['_id'],
        'game_invites.from_user': from_user_id,
        'game_invites.room_code': normalized_room_code
    })
    if duplicate_invite is not None:
        return True

    result = users_collection.update_one(
        {'_id': to_user['_id']},
        {'$push': {'game_invites': {
            'from_user': from_user_id,
            'room_code': normalized_room_code,
            'date': datetime.now().isoformat()
        }}}
    )
    return result.modified_count > 0

def remove_game_invite(to_user_id: ObjectId, from_user_id: ObjectId, room_code: str) -> bool:
    users_collection = database.db['users']
    normalized_room_code = room_code.strip().upper()
    result = users_collection.update_one(
        {'_id': to_user_id},
        {'$pull': {'game_invites': {
            'from_user': from_user_id,
            'room_code': normalized_room_code
        }}}
    )
    return result.modified_count > 0

def cancel_sent_game_invite(from_user_id: ObjectId, to_user_name: str, room_code: str) -> bool:
    users_collection = database.db['users']
    to_user = users_collection.find_one({'username': to_user_name})
    if to_user is None:
        return False

    normalized_room_code = room_code.strip().upper()
    result = users_collection.update_one(
        {'_id': to_user['_id']},
        {'$pull': {'game_invites': {
            'from_user': from_user_id,
            'room_code': normalized_room_code
        }}}
    )
    return result.modified_count > 0

def accept_friend_request(to_user_id: ObjectId, from_user_id: ObjectId) -> bool:
    users_collection = database.db['users']
    result = users_collection.update_one(
        {'_id': to_user_id, 'friend_requests.from_user': from_user_id},
        {'$pull': {'friend_requests': {'from_user': from_user_id}}}
    )
    if result.modified_count > 0:
        users_collection.update_one({'_id': to_user_id}, {'$push': {'friends': from_user_id}})
        users_collection.update_one({'_id': from_user_id}, {'$push': {'friends': to_user_id}})
        return True
    return False

def reject_friend_request(to_user_id: ObjectId, from_user_id: ObjectId) -> bool:
    users_collection = database.db['users']
    result = users_collection.update_one(
        {'_id': to_user_id, 'friend_requests.from_user': from_user_id},
        {'$pull': {'friend_requests': {'from_user': from_user_id}}}
    )
    return result.modified_count > 0

def remove_friend(user_id_1: ObjectId, user_id_2: ObjectId) -> bool:
    users_collection = database.db['users']
    result1 = users_collection.update_one({'_id': user_id_1}, {'$pull': {'friends': user_id_2}})
    result2 = users_collection.update_one({'_id': user_id_2}, {'$pull': {'friends': user_id_1}})
    return result1.modified_count > 0 and result2.modified_count > 0

def check_friendship(user_id_1: ObjectId, user_id_2: ObjectId) -> bool:
    friends = list_friends_ids(user_id_1)
    return user_id_2 in friends
