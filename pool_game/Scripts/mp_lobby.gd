extends Node3D

signal private_room_code_ready(code: String)
signal private_room_error(message: String)
signal private_room_closed_notice(reason: String)

var free_spots = [0]
var regular_games = {}

var regular_queue = []
var private_rooms = {}
var room_by_peer = {}
var game_id_by_player_pair: Dictionary = {}
var resume_waiting_by_game_id: Dictionary = {}
var resume_game_by_peer: Dictionary = {}
var peer_to_slot: Dictionary[int, int] = {}

var init_mp = null
var init_slot = null
var init_peers = null

var player_tokens: Dictionary[int, String] = {}
var player_info: Dictionary[int, Dictionary] = {}

@export var matchmaking_mode: int = Utils.MatchmakingMode.RANDOM
@export var pending_room_code: String = ""
@export var resume_game_id: String = ""

@onready var games = $Games
const lobby_scene = preload("res://Scenes/mp_lobby.tscn")
const reg_game_scene = preload("res://main.tscn")
const isolated_game = preload("res://Scenes/isolated_game.tscn")

@onready var info_label = $ClientUI/VBoxContainer/InfoLabel
@onready var exit_button = $ClientUI/VBoxContainer/ExitButton
@onready var backend_requests = $BackendRequests

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	exit_button.pressed.connect(_on_exit_clicked)
	
	if init_mp != null and init_slot != null and init_peers != null:
		get_tree().set_multiplayer(init_mp)
		var container = Node3D.new()
		container.name = "GameContainer%s" % init_slot
		var subview = Node3D.new()
		subview.name = "SubViewport"
		var game = reg_game_scene.instantiate()
		game.name = "Game"
		game.connected_peers = init_peers
		subview.add_child(game)
		container.add_child(subview)
		$"Games".add_child(container)
		game.start_game()
		return

	var args := OS.get_cmdline_args()
	var arg_seen = false
	for a in args:
		if a == "--server":
			start_server()
			arg_seen = true
			break
		elif a.begins_with("--connect="):
			var host = a.get_slice("=", 1)
			start_client(host)
			arg_seen = true
			break
	if not arg_seen:
		start_client("127.0.0.1")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
	
func _on_exit_clicked() -> void:
	request_leave_matchmaking.rpc_id(1)
	get_tree().change_scene_to_file("res://Menu.tscn")

func queue_random_match() -> void:
	matchmaking_mode = Utils.MatchmakingMode.RANDOM
	pending_room_code = ""
	_request_selected_matchmaking()

func create_private_room() -> void:
	matchmaking_mode = Utils.MatchmakingMode.PRIVATE_CREATE
	pending_room_code = ""
	_request_selected_matchmaking()

func join_private_room(code: String) -> void:
	matchmaking_mode = Utils.MatchmakingMode.PRIVATE_JOIN
	pending_room_code = _normalize_room_code(code)
	_request_selected_matchmaking()

func leave_matchmaking() -> void:
	request_leave_matchmaking.rpc()

func start_server(port: int = 18361) -> void:
	print("Starting server on port %d" % port)
	randomize()
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(port, 32)
	multiplayer.multiplayer_peer = peer
	multiplayer.connect("peer_connected", _on_peer_connected)
	multiplayer.connect("peer_disconnected", _on_peer_disconnected)
	multiplayer.connect("server_disconnected", _on_server_disconnected)

func _on_peer_connected(peer: int):
	print("peer connected: %d" % peer)

func _on_peer_disconnected(peer: int):
	print("peer disconnected: %d" % peer)
	if multiplayer.is_server():
		_remove_from_random_queue(peer)
		_remove_from_private_room(peer, true)
		_remove_from_resume_wait(peer, false)
	# close down the game if they were in one
	var slot = peer_to_slot.get(peer, null)
	if slot != null:
		close_game_at(slot)

func _on_server_disconnected():
	pass

func start_client(host: String, port: int = 18361) -> void:
	print("Connecting to server %s:%d" % [host, port])
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(host, port)
	multiplayer.multiplayer_peer = peer
	multiplayer.connect("connected_to_server", _on_connected_to_server)
	multiplayer.connect("connection_failed", _on_connection_failed)
	multiplayer.connect("server_disconnected", _on_server_disconnected)

func _on_connected_to_server():
	var token := ""
	var config := ConfigFile.new()
	if config.load("user://account.cfg") == OK:
		token = config.get_value("account", "session", "")
	auth.rpc_id(1, token)
	_request_selected_matchmaking()
	
func _on_connection_failed():
	pass

func _request_selected_matchmaking() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		return

	match matchmaking_mode:
		Utils.MatchmakingMode.PRIVATE_CREATE:
			request_create_private_room.rpc()
		Utils.MatchmakingMode.PRIVATE_JOIN:
			request_join_private_room.rpc(pending_room_code)
		Utils.MatchmakingMode.RESUME:
			request_resume_game.rpc(resume_game_id)
		_:
			enter_random_regular_queue.rpc()
	$ClientUI.show()

@rpc("any_peer")
func enter_random_regular_queue():
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_remove_from_private_room(sender_id, false)
	_remove_from_resume_wait(sender_id, true)
	if regular_queue.has(sender_id):
		return
	regular_queue.append(sender_id)
	_try_match_random_queue()

@rpc("any_peer")
func request_create_private_room():
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_remove_from_random_queue(sender_id)
	_remove_from_private_room(sender_id, false)
	_remove_from_resume_wait(sender_id, true)

	var code := _generate_unique_room_code()
	private_rooms[code] = {"host_id": sender_id, "guest_id": 0}
	room_by_peer[sender_id] = code
	private_room_created.rpc_id(sender_id, code)

@rpc("any_peer")
func request_join_private_room(code: String):
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var normalized_code := _normalize_room_code(code)
	_remove_from_random_queue(sender_id)
	_remove_from_private_room(sender_id, false)
	_remove_from_resume_wait(sender_id, true)

	if normalized_code.is_empty():
		private_room_join_failed.rpc_id(sender_id, "Room code is empty.")
		return
	if not private_rooms.has(normalized_code):
		private_room_join_failed.rpc_id(sender_id, "Room code not found.")
		return

	var room: Dictionary = private_rooms[normalized_code]
	var host_id := int(room["host_id"])
	var guest_id := int(room["guest_id"])
	if host_id == sender_id:
		private_room_join_failed.rpc_id(sender_id, "You cannot join your own room.")
		return
	if guest_id != 0:
		private_room_join_failed.rpc_id(sender_id, "Room is already full.")
		return

	room["guest_id"] = sender_id
	private_rooms[normalized_code] = room
	room_by_peer[sender_id] = normalized_code
	private_room_joined.rpc_id(host_id, normalized_code)
	private_room_joined.rpc_id(sender_id, normalized_code)

	private_rooms.erase(normalized_code)
	room_by_peer.erase(host_id)
	room_by_peer.erase(sender_id)
	_start_game_for_peers([host_id, sender_id])

@rpc("any_peer")
func request_resume_game(requested_game_id: String):
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	_remove_from_random_queue(sender_id)
	_remove_from_private_room(sender_id, false)
	_remove_from_resume_wait(sender_id, false)

	var token := _token_for_peer(sender_id)
	if token == "":
		resume_game_failed.rpc_id(sender_id, "You must be logged in to resume a game.")
		return

	var account_info: Dictionary = player_info.get(sender_id, {})
	if not (account_info is Dictionary) or not account_info.has("username"):
		account_info = await backend_requests.info_for_account(token)
		if account_info.has("username"):
			player_info[sender_id] = account_info

	if not (account_info is Dictionary):
		resume_game_failed.rpc_id(sender_id, "Failed to fetch account info.")
		return

	var profile_game_id := str(account_info.get("current_game_id", ""))
	var chosen_game_id := requested_game_id.strip_edges()
	if chosen_game_id == "":
		chosen_game_id = profile_game_id

	if chosen_game_id == "":
		resume_game_failed.rpc_id(sender_id, "No resumable game found for this account.")
		return

	if profile_game_id != "" and profile_game_id != chosen_game_id:
		resume_game_failed.rpc_id(sender_id, "Requested resume game no longer matches your account state.")
		return

	if not resume_waiting_by_game_id.has(chosen_game_id):
		resume_waiting_by_game_id[chosen_game_id] = []

	var waiting: Array = resume_waiting_by_game_id[chosen_game_id]
	if not waiting.has(sender_id):
		waiting.append(sender_id)
	resume_waiting_by_game_id[chosen_game_id] = waiting
	resume_game_by_peer[sender_id] = chosen_game_id

	var waiting_count := waiting.size()
	resume_game_waiting.rpc_id(sender_id, waiting_count)
	_try_match_resume_game(chosen_game_id)

func _try_match_resume_game(game_id: String) -> void:
	if not resume_waiting_by_game_id.has(game_id):
		return

	var waiting: Array = resume_waiting_by_game_id[game_id]
	while waiting.size() >= 2:
		var first = waiting.pop_front()
		var second = waiting.pop_front()
		resume_waiting_by_game_id[game_id] = waiting
		_remove_from_resume_wait(first, false)
		_remove_from_resume_wait(second, false)
		_start_game_for_peers([first, second], game_id)

	if waiting.is_empty() and resume_waiting_by_game_id.has(game_id):
		resume_waiting_by_game_id.erase(game_id)

@rpc("any_peer")
func request_cancel_private_room():
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_remove_from_private_room(sender_id, false)

@rpc("any_peer")
func request_leave_matchmaking():
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_remove_from_random_queue(sender_id)
	_remove_from_private_room(sender_id, true)
	_remove_from_resume_wait(sender_id, false)

@rpc("authority", "call_remote", "reliable")
func private_room_created(code: String):
	print("Private room created: %s" % code)
	info_label.text = code
	emit_signal("private_room_code_ready", code)

@rpc("authority", "call_remote", "reliable")
func private_room_joined(code: String):
	print("Joined room: %s" % code)

@rpc("authority", "call_remote", "reliable")
func private_room_join_failed(reason: String):
	print("Private room join failed: %s" % reason)
	info_label.text = "Private room join failed: %s" % reason
	emit_signal("private_room_error", reason)

@rpc("authority", "call_remote", "reliable")
func private_room_closed(reason: String):
	print("Private room closed: %s" % reason)
	emit_signal("private_room_closed_notice", reason)

@rpc("authority", "call_remote", "reliable")
func resume_game_waiting(waiting_count: int):
	info_label.text = "Waiting to resume... (%d/2)" % waiting_count

@rpc("authority", "call_remote", "reliable")
func resume_game_failed(reason: String):
	info_label.text = "Resume failed: %s" % reason

@rpc("authority", "call_remote", "reliable")
func send_to_game(slot: int, peers: Array):
	var container = games.get_node("GameContainer%s/SubViewportContainer" % slot)
	container.visible = true
	var game = container.get_node("SubViewport/Game")
	game.visible = true
	game.connected_peers = peers
	var camera = game.get_node("CameraPivot/Camera3D")
	camera.make_current()
	$ClientUI.hide()

func _try_match_random_queue() -> void:
	while regular_queue.size() >= 2:
		var first = regular_queue.pop_front()
		var second = regular_queue.pop_front()
		_start_game_for_peers([first, second])

func _start_game_for_peers(peers: Array, forced_game_id: String = "") -> void:
	var game = spawn_new_regular_game()
	var persistence_context := await _build_persistence_context(peers)
	if forced_game_id != "":
		persistence_context["game_id"] = forced_game_id
		persistence_context["enabled"] = true
	game.persistence_enabled = bool(persistence_context["enabled"])
	game.persistence_usernames = persistence_context["usernames"]
	game.persistence_tokens = persistence_context["tokens"]
	game.persistence_pair_key = str(persistence_context["pair_key"])
	game.persisted_game_id = str(persistence_context["game_id"])
	game.connected_peers = peers
	for peer_id in peers:
		peer_to_slot[peer_id] = game.lobby_slot
		send_to_game.rpc_id(int(peer_id), game.lobby_slot, peers)

	if game.persistence_enabled and game.persisted_game_id != "":
		var load_token: String = str(persistence_context["load_token"])
		var state: Dictionary = await backend_requests.get_game_state(load_token, game.persisted_game_id)
		if state.is_empty():
			game.start_game()
		else:
			game.load(state)
			game.set_visibility.rpc()
	else:
		game.start_game()

func register_game_id_for_pair(pair_key: String, game_id: String) -> void:
	if pair_key == "" or game_id == "":
		return
	game_id_by_player_pair[pair_key] = game_id

func _build_persistence_context(peers: Array) -> Dictionary:
	var usernames: Array[String] = []
	var tokens: Array[String] = []
	for peer in peers:
		var peer_id := int(peer)
		var token := _token_for_peer(peer_id)
		var username := _username_for_peer(peer_id)

		if username == "" and token != "":
			var info: Dictionary = await backend_requests.info_for_account(token)
			if info.has("username"):
				player_info[peer_id] = info
				username = str(info["username"])

		usernames.append(username)
		tokens.append(token)

	var enabled := usernames.size() == 2 and usernames[0] != "" and usernames[1] != ""
	var pair_key := ""
	var game_id := ""
	var load_token := ""
	if enabled:
		pair_key = _pair_key_for_usernames(usernames)
		game_id = str(game_id_by_player_pair.get(pair_key, ""))
		load_token = tokens[0] if tokens[0] != "" else tokens[1]

	return {
		"enabled": enabled,
		"usernames": usernames,
		"tokens": tokens,
		"pair_key": pair_key,
		"game_id": game_id,
		"load_token": load_token,
	}

func _username_for_peer(peer_id: int) -> String:
	if not player_info.has(peer_id):
		return ""
	var info = player_info[peer_id]
	if typeof(info) != TYPE_DICTIONARY:
		return ""
	if not info.has("username"):
		return ""
	return str(info["username"])

func _token_for_peer(peer_id: int) -> String:
	if not player_tokens.has(peer_id):
		return ""
	return str(player_tokens[peer_id])

func _pair_key_for_usernames(usernames: Array[String]) -> String:
	var sorted_names := usernames.duplicate()
	sorted_names.sort()
	return "%s|%s" % [sorted_names[0], sorted_names[1]]

func _remove_from_random_queue(peer_id: int) -> void:
	while regular_queue.has(peer_id):
		regular_queue.erase(peer_id)

func _remove_from_resume_wait(peer_id: int, call_leave_game: bool) -> void:
	if resume_game_by_peer.has(peer_id):
		var game_id: String = str(resume_game_by_peer[peer_id])
		resume_game_by_peer.erase(peer_id)
		if resume_waiting_by_game_id.has(game_id):
			var waiting: Array = resume_waiting_by_game_id[game_id]
			while waiting.has(peer_id):
				waiting.erase(peer_id)
			if waiting.is_empty():
				resume_waiting_by_game_id.erase(game_id)
			else:
				resume_waiting_by_game_id[game_id] = waiting

	if call_leave_game:
		var token := _token_for_peer(peer_id)
		if token != "":
			backend_requests.leave_game(token)

func _remove_from_private_room(peer_id: int, notify_other: bool) -> void:
	if not room_by_peer.has(peer_id):
		return

	var code: String = room_by_peer[peer_id]
	room_by_peer.erase(peer_id)
	if not private_rooms.has(code):
		return

	var room: Dictionary = private_rooms[code]
	var host_id := int(room["host_id"])
	var guest_id := int(room["guest_id"])

	if host_id == peer_id:
		private_rooms.erase(code)
		if notify_other and guest_id != 0:
			private_room_closed.rpc_id(guest_id, "Host left room.")
			room_by_peer.erase(guest_id)
		return

	if guest_id == peer_id:
		room["guest_id"] = 0
		private_rooms[code] = room
		if notify_other and host_id != 0:
			private_room_closed.rpc_id(host_id, "Guest left room.")
		return

func _normalize_room_code(raw_code: String) -> String:
	return raw_code.strip_edges().replace(" ", "-").to_upper()

func _generate_unique_room_code() -> String:
	for i in range(64):
		var code := "%s-%s-%s" % [
			Utils.word_list[randi() % Utils.word_list.size()],
			Utils.word_list[randi() % Utils.word_list.size()],
			Utils.word_list[randi() % Utils.word_list.size()]
		]
		if not private_rooms.has(code):
			return code
	return "ROOM-%d" % Time.get_unix_time_from_system()

@rpc("any_peer", "call_remote", "reliable")
func auth(token: String):
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	player_tokens[sender_id] = token
	if token == "":
		player_info.erase(sender_id)
		return

	print("got token from peer %d" % sender_id)
	var info = await backend_requests.info_for_account(token)
	if info.has("username"):
		player_info[sender_id] = info
		print("got player info for peer %d: %s" % [sender_id, str(info)])
	else:
		player_info.erase(sender_id)

func spawn_new_regular_game() -> Node:
	var spot = free_spots[0]
	free_spots.remove_at(0)

	var isolated: Node3D = isolated_game.instantiate()
	isolated.name = "GameContainer%s" % spot
	var game = isolated.get_node("SubViewportContainer/SubViewport/Game")
	regular_games[spot] = game
	game.lobby_slot = spot
	games.add_child(isolated)

	print("putting game in spot " + str(spot))
	if free_spots.size() == 0:
		free_spots.append(spot + 1)
	return game
	
@rpc
func send_to_menu():
	get_tree().change_scene_to_file("res://Menu.tscn") 

func close_game_at(spot: int):
	var game = regular_games.get(spot, null)
	if game == null:
		return
	game.stopped_moving.connect(func():
		despawn_game_at(spot)
	)
	if game.game_state != Utils.GameState.MIDTURN:
		despawn_game_at(spot)

func despawn_game_at(spot: int):
	var peers_to_remove = []
	for peer_id in peer_to_slot.keys():
		if peer_to_slot[peer_id] == spot:
			peers_to_remove.append(peer_id)
	for peer_id in peers_to_remove:
		peer_to_slot.erase(peer_id)
		player_tokens.erase(peer_id)
		send_to_menu.rpc_id(peer_id)
	var game = regular_games[spot]
	regular_games.erase(spot)
	var fs_pos = free_spots.bsearch(spot)
	free_spots.insert(fs_pos, spot)
	games.remove_child(game)
	game.queue_free()
