extends HTTPRequest


var config := ConfigFile.new()
# TODO: use env var or config
const BACKEND_URL := "http://127.0.0.1:5000"

var session: String

enum PlayerRole {STRIPES = 1, SOLIDS}
enum GameType {EIGHT_BALL_MULTIPLAYER = 1, EIGHT_BALL_SINGLEPLAYER, CRAZY_EIGHT_BALL_MULTIPLAYER, CRAZY_EIGHT_BALL_SINGLEPLAYER}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# TODO: probably should not be stored in plaintext in a config file
	if config.load("user://account.cfg") == OK:
		session = config.get_value("account", "session", "")
	request_completed.connect(_on_request_completed)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

class GameInstance:
	var game_id: String
	var player_roles: Dictionary # dict[ObjectId, PlayerRole]
	var game_type: Utils.GameType = Utils.GameType.EIGHT_BALL_MULTIPLAYER
	var player_points: Dictionary # dict[ObjectId, int]
	var current_turn: int
	var ball_positions: Dictionary # dict[int, tuple[float, float, float]]
	var ball_rotations: Dictionary # dict[int, tuple[float, float, float]]
	
func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	print("Request completed with result: " + str(result) + ", response code: " + str(response_code))
	print("Headers: " + str(headers))
	print("Body: " + str(body.get_string_from_utf8()))
	
# not sure if doing this is necessary but I want to avoid possible race conditions for multiple requests at the same time
func _make_request(url: String, method: int, json_body: Dictionary = {}, session_token = null) -> Dictionary:
	var req := HTTPRequest.new()
	
	add_child(req)
	var body_text := "" if json_body == {} else JSON.stringify(json_body)
	var headers := ["Content-Type: application/json"]
	if session_token != null and session_token != "":
		headers.append("Cookie: session=" + session_token)
	elif session != null and session != "":
		headers.append("Cookie: session=" + session)
	var err := req.request(url, headers, method, body_text)
	if err != OK:
		req.queue_free()
		return {"error": "request_start_failed", "code": err}

	var res = await req.request_completed
	var result = res[0]
	var response_code = res[1]
	var resp_headers = res[2]
	var body = res[3]
	var body_text_resp := ""
	if body != null:
		body_text_resp = body.get_string_from_utf8()

	req.queue_free()

	if result != OK:
		return {"error": "http_transport_error", "result": result, "response_code": response_code, "body": body_text_resp}

	return {"result": body_text_resp, "response_code": response_code, "headers": resp_headers}

func register(username: String, password: String) -> Dictionary:
	var url: String = BACKEND_URL + "/register"
	var body: Dictionary[Variant, Variant] = {"username": username, "password": password}
	var response: Dictionary = await _make_request(url, HTTPClient.METHOD_POST, body)
	print(response)
	return response
	
func login(username: String, password: String) -> Dictionary:
	var url: String = BACKEND_URL + "/login"
	var body: Dictionary[Variant, Variant] = {"username": username, "password": password}
	var response: Dictionary = await _make_request(url, HTTPClient.METHOD_POST, body)
	if "headers" in response and "response_code" in response and response["response_code"] == 200:
		for header in response["headers"]:
			if header.begins_with("Set-Cookie:"):
				var cookie_value = header.substr("Set-Cookie: ".length()).strip_edges()
				cookie_value = cookie_value.split("; ")
				for part in cookie_value:
					if part.begins_with("session="):
						session = part.substr("session=".length()).strip_edges()
						config.set_value("account", "session", session)
						config.save("user://account.cfg")
						break
	else:
		print("Login failed with response code: " + str(response["response_code"]))
	return response
	
func info_for_account(token: String) -> Dictionary:
	var url: String = BACKEND_URL + "/profile"
	var response: Dictionary = await _make_request(url, HTTPClient.METHOD_GET, {}, token)
	print(response)
	if "result" in response:
		var json := JSON.new()
		var err := json.parse(response["result"])
		if err == OK:
			return json.get_data()
		else:
			print("Failed to parse JSON response: " + str(err))
			return {}
	else:
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
