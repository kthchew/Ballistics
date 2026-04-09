extends HTTPRequest


var config := ConfigFile.new()

var session: String

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# TODO: probably should not be stored in plaintext in a config file
	if config.load("user://account.cfg") == OK:
		session = config.get_value("account", "session", "")
	request_completed.connect(_on_request_completed)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func backend_url() -> String:
	return config.get_value("network", "backend_url", "http://127.0.0.1:5000")

class GameInstance:
	var game_id: String
	var player_roles: Dictionary # dict[ObjectId, PlayerRole]
	var game_type: Utils.GameType = Utils.GameType.EIGHT_BALL_MULTIPLAYER
	var game_state: Utils.GameState
	var player_points: Dictionary # dict[ObjectId, int]
	var current_turn_number: int
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
	var url: String = backend_url() + "/register"
	var body: Dictionary[Variant, Variant] = {"username": username, "password": password}
	var response: Dictionary = await _make_request(url, HTTPClient.METHOD_POST, body)
	print(response)
	return response
	
func login(username: String, password: String) -> Dictionary:
	var url: String = backend_url() + "/login"
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
	var url: String = backend_url() + "/profile"
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
	
func join_game(token: String, game_id: String) -> bool:
	var url = backend_url() + "/joinGame"
	var body = {"game_id": game_id}
	var response: Dictionary = await _make_request(url, HTTPClient.METHOD_POST, body, token)
	return response["response_code"] == 200
	
func leave_game(token: String) -> bool:
	var url = backend_url() + "/leaveGame"
	var response: Dictionary = await _make_request(url, HTTPClient.METHOD_POST, {}, token)
	return response["response_code"] == 200
	

## Saves a new game to the backend and returns the game ID. This should only be called from the game server.
func create_new_game(game_state: Dictionary) -> String:
	var url = backend_url() + "/newGame"
	var body = {"game_state": game_state}
	var response: Dictionary = await _make_request(url, HTTPClient.METHOD_POST, body)
	if "result" in response:
		var json := JSON.new()
		var err := json.parse(response["result"])
		if err == OK:
			var result_dict = json.get_data()
			if "game_id" in result_dict:
				return result_dict["game_id"]
			else:
				print("Failed to create game, no game_id in response: " + str(result_dict))
				return ""
		else:
			print("Failed to parse JSON response: " + str(err))
			return ""
	else:
		print("Failed to create game, no result in response: " + str(response))
		return ""

func get_game_state(token: String, game_id: String) -> Dictionary:
	var url = backend_url() + "/getGame"
	var body = {"token": token, "game_id": game_id}
	var response: Dictionary = await _make_request(url, HTTPClient.METHOD_GET, body, token)
	if not response.has("result"):
		print("Failed to get game state, no result in response: " + str(response))
		return {}
	var json := JSON.new()
	var err := json.parse(response["result"])
	if err == OK:
		var result_dict = json.get_data()
		return result_dict
	else:
		print("Failed to parse JSON response: " + str(err))
		return {}

func set_game_state(state: Dictionary, game_id: String) -> bool:
	var url = backend_url() + "/updateGame"
	var body = {"game_state": state, "game_id": game_id}
	var response: Dictionary = await _make_request(url, HTTPClient.METHOD_POST, body)
	return response["response_code"] == 200
