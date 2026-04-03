import os

import bson.errors
from bson import ObjectId

import accounts
import game
import json

from flask import Flask, session, request, jsonify
from game import GameInstance

app = Flask(__name__)
app.secret_key = os.environ['BALLISTIC_SERV_SECRET_KEY']


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
    return jsonify(game.game_instance_to_mongo_dict(game_instance))

# FIXME: anything below this should be restricted to requests from a trusted Godot game server
@app.post("/newGame")
def new_game():
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
