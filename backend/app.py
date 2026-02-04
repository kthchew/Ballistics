import os

from flask import Flask, session, request
import accounts

app = Flask(__name__)
app.secret_key = os.environ['BALLISTIC_SERV_SECRET_KEY']

@app.post("/register")
def register():
    json = request.get_json()
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
    return f"Profile of {session['username']}", 200
