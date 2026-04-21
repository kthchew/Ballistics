import os

import bson.errors
from bson import ObjectId

import accounts
import game
import json
import random
import string
import socket
import ipaddress

from flask import Flask, session, request, jsonify
from game import GameInstance

app = Flask(__name__)
app.secret_key = os.environ['BALLISTIC_SERV_SECRET_KEY']


def _generate_room_code() -> str:
    alphabet = string.ascii_uppercase + string.digits
    chunks = ["".join(random.choice(alphabet) for _ in range(4)) for _ in range(3)]
    return "-".join(chunks)


def is_local_host(host: str | None) -> bool:
    """
    To lock certain endpoints to localhost:
    1. Put this service behind a reverse proxy (we use Caddy) that sets the X-Forwarded-For header.
    2. Check the X-Forwarded-For header against this function.
    3. In /etc/hosts on the server, set the hostname to 127.0.0.1.

    :param host: A hostname or IP address.
    :return: Whether the host is localhost.
    """
    if host is None:
        return False

    host_ip = socket.gethostbyname(host)
    return ipaddress.ip_address(host_ip).is_loopback

@app.post("/register")
def register():
    json = request.get_json()
    if 'username' not in json or 'password' not in json:
        return "Bad request", 400
    username = json['username']
    password = json['password']
    try:
        accounts.register_user(username, password)
        session['username'] = username
        return "User registered successfully", 201
    except ValueError as e:
        return str(e), 400


@app.post("/login")
def login_with_password():
    json = request.get_json()
    if 'username' not in json or 'password' not in json:
        return "Bad request", 400
    username = json['username']
    password = json['password']
    if accounts.check_valid_login(username, password):
        session['username'] = username
        return "User logged in successfully", 200
    else:
        return "Invalid username or password", 401


@app.post("/logout")
def logout():
    session.pop('username', None)
    return "Logged out", 200


@app.get("/session")
def get_session_state():
    username = session.get('username')
    if username is None:
        return jsonify({'logged_in': False, 'username': None})
    return jsonify({'logged_in': True, 'username': username})


@app.get("/profile")
def profile():
    if 'username' not in session:
        return "Unauthorized", 401
    try:
        account = accounts.get_info(session['username'])
        return jsonify(account), 200
    except ValueError:
        return "Unauthorized", 401

@app.post("/joinGame")
def join_game():
    if 'username' not in session:
        return "Unauthorized", 401
    json = request.get_json()
    if 'game_id' not in json:
        return "Bad request", 400

    game_id = json['game_id']
    if accounts.join_game(session['username'], game_id):
        return f"User {session['username']} joined game {game_id}", 200
    else:
        return "Failed to join game", 500


@app.post("/leaveGame")
def leave_game():
    if 'username' not in session:
        return "Unauthorized", 401
    if accounts.leave_game(session['username']):
        return f"User {session['username']} left their current game", 200
    else:
        return "Failed to leave game", 500

@app.get("/getGame")
def get_game():
    if 'username' not in session:
        return "Unauthorized", 401
    username = session['username']
    users_collection = accounts.database.db['users']
    user = users_collection.find_one({'username': username})
    if user is None:
        return "User not found", 401
    current_game_id = user['current_game_id']
    if current_game_id is None:
        return "User is not in a game", 400
    game_instance = game.get_game_state(current_game_id)
    game_instance['_id'] = str(game_instance['_id'])
    return jsonify(game_instance)

@app.get("/friends")
def get_friends():
    if 'username' not in session:
        return "Unauthorized"
    username = session['username']
    id = accounts.username_to_id(username)
    if id is None:
        return "User not found", 401
    friends_ids = accounts.list_friends_ids(id)
    users_collection = accounts.database.db['users']
    friends = []
    for friend_id in friends_ids:
        friend = users_collection.find_one({'_id': friend_id})
        if friend is not None:
            friends.append(friend['username'])
    return jsonify(friends)

@app.post("/friends/remove")
def remove_friend():
    if 'username' not in session:
        return "Unauthorized"
    json_data = request.get_json()
    if 'defriend' not in json_data:
        return "Bad request", 400
    friend_username = json_data['defriend']
    username = session['username']
    user_id = accounts.username_to_id(username)
    friend_user_id = accounts.username_to_id(friend_username)
    if user_id is None or friend_user_id is None:
        return "User not found", 401
    if accounts.remove_friend(user_id, friend_user_id):
        return f"Friend {friend_username} removed successfully", 200
    else:
        return "Failed to remove friend", 500

@app.get("/friendRequests")
def get_friend_requests():
    if 'username' not in session:
        return "Unauthorized"
    username = session['username']
    id = accounts.username_to_id(username)
    if id is None:
        return "User not found", 401
    f_requests = accounts.list_friend_requests(id)
    requests = []
    for f_request in f_requests:
        from_username = accounts.id_to_username(f_request['from_user'])
        if from_username is not None:
            requests.append({
                'from_user': from_username,
                'date': f_request['date']
            })
    return jsonify(requests)

@app.get("/friends/check")
def check_friendship():
    if 'username' not in session:
        return "Unauthorized"
    other_username = request.args.get('other_user')
    if other_username is None:
        return "Bad request", 400
    username = session['username']
    user_id = accounts.username_to_id(username)
    other_user_id = accounts.username_to_id(other_username)
    if user_id is None:
        return "User not found", 401
    if other_user_id is None:
        return "0", 200
    if accounts.check_friendship(user_id, other_user_id):
        return "1", 200
    else:
        return "0", 200

@app.post("/friendRequests/send")
def send_friend_request():
    if 'username' not in session:
        return "Unauthorized"
    json_data = request.get_json()
    if 'to_user' not in json_data:
        return "Bad request", 400
    to_user_name = json_data['to_user']
    username = session['username']
    from_user_id = accounts.username_to_id(username)
    if from_user_id is None:
        return "User not found", 401
    if accounts.send_friend_request(from_user_id, to_user_name):
        return f"Friend request sent to {to_user_name}", 200
    else:
        return "Failed to send friend request", 500

@app.post("/friendRequests/accept")
def accept_friend_request():
    if 'username' not in session:
        return "Unauthorized"
    json_data = request.get_json()
    if 'from_user' not in json_data:
        return "Bad request", 400
    from_user_name = json_data['from_user']
    username = session['username']
    to_user_id = accounts.username_to_id(username)
    from_user_id = accounts.username_to_id(from_user_name)
    if to_user_id is None or from_user_id is None:
        return "User not found", 401
    if accounts.accept_friend_request(to_user_id, from_user_id):
        return f"Friend request from {from_user_name} accepted", 200
    else:
        return "Failed to accept friend request", 500

@app.post("/friendRequests/reject")
def reject_friend_request():
    if 'username' not in session:
        return "Unauthorized"
    json_data = request.get_json()
    if 'from_user' not in json_data:
        return "Bad request", 400
    from_user_name = json_data['from_user']
    username = session['username']
    to_user_id = accounts.username_to_id(username)
    from_user_id = accounts.username_to_id(from_user_name)
    if to_user_id is None or from_user_id is None:
        return "User not found", 401
    if accounts.reject_friend_request(to_user_id, from_user_id):
        return f"Friend request from {from_user_name} rejected", 200
    else:
        return "Failed to reject friend request", 500


@app.get("/gameInvites")
def get_game_invites():
    if 'username' not in session:
        return "Unauthorized", 401
    username = session['username']
    user_id = accounts.username_to_id(username)
    if user_id is None:
        return "User not found", 401

    invites = []
    for invite in accounts.list_game_invites(user_id):
        from_username = accounts.id_to_username(invite['from_user'])
        if from_username is None:
            continue
        invites.append({
            'from_user': from_username,
            'room_code': invite['room_code'],
            'date': invite['date']
        })
    return jsonify(invites)


@app.post("/gameInvites/send")
def send_game_invite():
    if 'username' not in session:
        return "Unauthorized", 401
    json_data = request.get_json()
    if 'to_user' not in json_data:
        return "Bad request", 400

    to_user_name = json_data['to_user']
    room_code = json_data.get('room_code', _generate_room_code())
    from_user_id = accounts.username_to_id(session['username'])
    if from_user_id is None:
        return "User not found", 401

    if accounts.send_game_invite(from_user_id, to_user_name, room_code):
        return jsonify({'message': f'Game invite sent to {to_user_name}', 'room_code': room_code}), 200
    return "Failed to send game invite", 500


@app.post("/gameInvites/remove")
def remove_game_invite():
    if 'username' not in session:
        return "Unauthorized", 401
    json_data = request.get_json()
    if 'from_user' not in json_data or 'room_code' not in json_data:
        return "Bad request", 400

    from_user_name = json_data['from_user']
    room_code = json_data['room_code']
    to_user_id = accounts.username_to_id(session['username'])
    from_user_id = accounts.username_to_id(from_user_name)
    if to_user_id is None or from_user_id is None:
        return "User not found", 401

    if accounts.remove_game_invite(to_user_id, from_user_id, room_code):
        return "Game invite removed", 200
    return "Failed to remove game invite", 500


@app.post("/gameInvites/cancel")
def cancel_sent_game_invite():
    if 'username' not in session:
        return "Unauthorized", 401
    json_data = request.get_json()
    if 'to_user' not in json_data or 'room_code' not in json_data:
        return "Bad request", 400

    to_user_name = json_data['to_user']
    room_code = json_data['room_code']
    from_user_id = accounts.username_to_id(session['username'])
    if from_user_id is None:
        return "User not found", 401

    removed = accounts.cancel_sent_game_invite(from_user_id, to_user_name, room_code)
    if removed:
        return "Game invite cancelled", 200
    return "Game invite was already cleared", 200

@app.post("/newGame")
def new_game():
    forwarded_for = request.headers.get('X-Forwarded-For')
    if not is_local_host(forwarded_for):
        return "Unauthorized", 401
    json_req = request.get_json()
    if 'game_state' not in json_req:
        return "Bad request", 400
    try:
        game_state = json_req['game_state']
        result = game.create_game(game_state)
        return {
            'result': 'Game created successfully',
            'game_id': str(result),
        }, 200
    except json.JSONDecodeError:
        return {'result': "Invalid JSON"}, 400
    except (TypeError, bson.errors.InvalidId) as e:
        return {'result': "Invalid request"}, 400

@app.post("/updateGame")
def update_game_state():
    forwarded_for = request.headers.get('X-Forwarded-For')
    if not is_local_host(forwarded_for):
        return "Unauthorized", 401
    json_req = request.get_json()
    if 'game_state' not in json_req or 'game_id' not in json_req:
        return "Bad request", 400
    try:
        game_state = json_req['game_state']
        game_id = ObjectId(json_req['game_id'])
    except json.JSONDecodeError:
        return "Invalid JSON", 400
    except (TypeError, bson.errors.InvalidId) as e:
        return "Invalid request", 400
    result = game.update_game_state(game_id, game_state)
    if result:
        return "Game state updated successfully", 200
    else:
        return "Failed to update game state", 500
