extends HTTPRequest


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

# TODO: use env var or config
const BACKEND_URL = "http://127.0.0.1:5000"

enum PlayerRole {STRIPES = 1, SOLIDS}
enum GameType {EIGHT_BALL_MULTIPLAYER = 1, EIGHT_BALL_SINGLEPLAYER, CRAZY_EIGHT_BALL_MULTIPLAYER, CRAZY_EIGHT_BALL_SINGLEPLAYER}

class GameInstance:
	var game_id: String
	var player_roles: Dictionary # dict[ObjectId, PlayerRole]
	var game_type: GameType
	var player_points: Dictionary # dict[ObjectId, int]
	var current_turn: int
	var ball_positions: Dictionary # dict[int, tuple[float, float]]
	var ball_rotations: Dictionary # dict[int, tuple[float, float]]

func register(username: String, password: String) -> Dictionary:
	var url = BACKEND_URL + "/register"
	var body = {"username": username, "password": password}
	var response = request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	#return JSON.parse(response.get_body_as_string()).result
	return {}
	
func login(username: String, password: String) -> Dictionary:
	var url = BACKEND_URL + "/login"
	var body = {"username": username, "password": password}
	var response = request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	#return JSON.parse(response.get_body_as_string()).result
	return {}
	
#func join_game(token: String, game_id: String) -> Dictionary:
	#var url = BACKEND_URL + "/joinGame"
	#var body = {"token": token, "game_id": game_id}
	#var response = HTTPRequest.request(url, [], true, HTTPClient.METHOD_POST, JSON.print(body))
	#return JSON.parse(response.get_body_as_string()).result
	#
#func leave_game(token: String, game_id: String) -> Dictionary:
	#var url = BACKEND_URL + "/leaveGame"
	#var body = {"token": token, "game_id": game_id}
	#var response = HTTPRequest.request(url, [], true, HTTPClient.METHOD_POST, JSON.print(body))
	#return JSON.parse(response.get_body_as_string()).result
	#
#func get_game_state(token: String, game_id: String) -> Dictionary:
	#var url = BACKEND_URL + "/getGame"
	#var body = {"token": token, "game_id": game_id}
	#var response = HTTPRequest.request(url, [], true, HTTPClient.METHOD_POST, JSON.print(body))
	#return JSON.parse(response.get_body_as_string()).result
	#
#func set_game_state(state: Dictionary) -> Dictionary:
	#var url = BACKEND_URL + "/setGame"
	#var body = {"game_state": state}
	#var response = HTTPRequest.request(url, [], true, HTTPClient.METHOD_POST, JSON.print(body))
	#return JSON.parse(response.get_body_as_string()).result
