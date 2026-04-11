extends HTTPRequest


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

# TODO: use env var or config
var BACKEND_URL: String = Constants.DEFAULT_ACCOUNT_SERVER_URL_DEV if OS.is_debug_build() else Constants.DEFAULT_ACCOUNT_SERVER_URL
const SESSION_CONFIG_PATH := "user://auth_session.cfg"

var session: String

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

func _load_session() -> void:
	var config := ConfigFile.new()
	var err := config.load(SESSION_CONFIG_PATH)
	if err != OK:
		return
	session = str(config.get_value("auth", "session", ""))

func _save_session() -> void:
	var config := ConfigFile.new()
	config.set_value("auth", "session", session)
	config.save(SESSION_CONFIG_PATH)

func _update_session_from_headers(response: Dictionary) -> void:
	if not ("headers" in response):
		return
	for header in response["headers"]:
		if not str(header).begins_with("Set-Cookie:"):
			continue
		var cookie_value = str(header).substr("Set-Cookie: ".length()).strip_edges()
		for part in cookie_value.split("; "):
			if part.begins_with("session="):
				session = part.substr("session=".length()).strip_edges()
				_save_session()
				return

func _parse_json_body(response: Dictionary, fallback: Variant) -> Variant:
	if not ("result" in response):
		return fallback
	var parsed = JSON.parse_string(str(response["result"]))
	if parsed == null:
		return fallback
	return parsed
	
# not sure if doing this is necessary but I want to avoid possible race conditions for multiple requests at the same time
func _make_request(url: String, method: int, json_body: Dictionary = {}) -> Dictionary:
	var req := HTTPRequest.new()
	
	add_child(req)
	var body_text := "" if json_body == {} else JSON.stringify(json_body)
	var headers := ["Content-Type: application/json"]
	if session != null and session != "":
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
	_update_session_from_headers(response)
	print(response)
	return response
	
func login(username: String, password: String) -> Dictionary:
	var url: String = BACKEND_URL + "/login"
	var body: Dictionary[Variant, Variant] = {"username": username, "password": password}
	var response: Dictionary = await _make_request(url, HTTPClient.METHOD_POST, body)
	if "response_code" in response and response["response_code"] == 200:
		_update_session_from_headers(response)
	else:
		print("Login failed with response code: " + str(response["response_code"]))
	return response

func get_session_state() -> Dictionary:
	var response: Dictionary = await _make_request(BACKEND_URL + "/session", HTTPClient.METHOD_GET)
	if response.get("response_code", 0) != 200:
		return {"logged_in": false, "username": ""}
	var payload = _parse_json_body(response, {})
	if typeof(payload) != TYPE_DICTIONARY:
		return {"logged_in": false, "username": ""}
	return payload

func logout() -> Dictionary:
	var response: Dictionary = await _make_request(BACKEND_URL + "/logout", HTTPClient.METHOD_POST, {})
	session = ""
	_save_session()
	return response

func get_friends() -> Array:
	var response: Dictionary = await _make_request(BACKEND_URL + "/friends", HTTPClient.METHOD_GET)
	var payload = _parse_json_body(response, [])
	if typeof(payload) != TYPE_ARRAY:
		return []
	return payload

func send_friend_request(to_user: String) -> Dictionary:
	return await _make_request(
		BACKEND_URL + "/friendRequests/send",
		HTTPClient.METHOD_POST,
		{"to_user": to_user}
	)

func get_friend_requests() -> Array:
	var response: Dictionary = await _make_request(BACKEND_URL + "/friendRequests", HTTPClient.METHOD_GET)
	var payload = _parse_json_body(response, [])
	if typeof(payload) != TYPE_ARRAY:
		return []
	return payload

func accept_friend_request(from_user: String) -> Dictionary:
	return await _make_request(
		BACKEND_URL + "/friendRequests/accept",
		HTTPClient.METHOD_POST,
		{"from_user": from_user}
	)

func reject_friend_request(from_user: String) -> Dictionary:
	return await _make_request(
		BACKEND_URL + "/friendRequests/reject",
		HTTPClient.METHOD_POST,
		{"from_user": from_user}
	)

func send_game_invite(to_user: String, room_code: String) -> Dictionary:
	return await _make_request(
		BACKEND_URL + "/gameInvites/send",
		HTTPClient.METHOD_POST,
		{"to_user": to_user, "room_code": room_code}
	)

func get_game_invites() -> Array:
	var response: Dictionary = await _make_request(BACKEND_URL + "/gameInvites", HTTPClient.METHOD_GET)
	var payload = _parse_json_body(response, [])
	if typeof(payload) != TYPE_ARRAY:
		return []
	return payload

func remove_game_invite(from_user: String, room_code: String) -> Dictionary:
	return await _make_request(
		BACKEND_URL + "/gameInvites/remove",
		HTTPClient.METHOD_POST,
		{"from_user": from_user, "room_code": room_code}
	)

func cancel_game_invite(to_user: String, room_code: String) -> Dictionary:
	return await _make_request(
		BACKEND_URL + "/gameInvites/cancel",
		HTTPClient.METHOD_POST,
		{"to_user": to_user, "room_code": room_code}
	)
	
func profile_test_endpoint() -> Dictionary:
	var url: String = BACKEND_URL + "/profile"
	var response: Dictionary = await _make_request(url, HTTPClient.METHOD_GET, {})
	print(response)
	return response

func _ready() -> void:
	_load_session()
	request_completed.connect(_on_request_completed)
	
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
