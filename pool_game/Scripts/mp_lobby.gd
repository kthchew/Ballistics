extends Node3D

signal private_room_code_ready(code: String)
signal private_room_error(message: String)
signal private_room_closed_notice(reason: String)

var free_spots = [0]
var regular_games = {}
var regular_queue = []
var crazy_queue = []
var crazy_games = {}
var private_rooms = {}
var room_by_peer = {}

var init_mp = null
var init_slot = null
var init_peers = null

var config := ConfigFile.new()
const CONFIG_PATH := "user://settings.cfg"

@export var matchmaking_mode = Utils.MatchmakingMode.RANDOM_NORMAL
@export var pending_room_code := ""

@onready var games = $Games
const lobby_scene = preload("res://Scenes/mp_lobby.tscn")
const reg_game_scene = preload("res://Scenes/main.tscn")
const isolated_game = preload("res://Scenes/isolated_game.tscn")

@onready var title_label = $ClientUI/VBoxContainer/TitleLabel
@onready var info_label = $ClientUI/VBoxContainer/InfoLabel
@onready var exit_button = $ClientUI/VBoxContainer/ExitButton

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
		
	var err := config.load(CONFIG_PATH)
	if err != OK:
		print("No existing config file found, using defaults")
	var args := OS.get_cmdline_args()
	var remote_addr = config.get_value("network", "server_address", "")
	var remote_port = config.get_value("network", "server_port", 18361)
	var arg_seen := false
	for a in args:
		if a == "--server":
			start_server()
			arg_seen = true
			break
		elif a.begins_with("--connect="):
			var host = a.get_slice("=", 1) if remote_addr == "" else remote_addr
			start_client(host, remote_port)
			arg_seen = true
			break
	if not arg_seen:
		start_client("127.0.0.1" if remote_addr == "" else remote_addr, remote_port)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
	
func _on_exit_clicked() -> void:
	request_leave_matchmaking.rpc_id(1)
	get_tree().change_scene_to_file("res://Scenes/Menu.tscn")

func queue_random_match() -> void:
	matchmaking_mode = Utils.MatchmakingMode.RANDOM_NORMAL
	pending_room_code = ""
	_request_selected_matchmaking()

func create_private_room() -> void:
	# FIXME: don't assume normal game
	matchmaking_mode = Utils.MatchmakingMode.PRIVATE_NORMAL_CREATE
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
	var mp_peer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	mp_peer.get_peer(peer).set_timeout(32, 180000, 300000)
	print("peer connected: %d" % peer)

func _on_peer_disconnected(peer: int):
	print("peer disconnected: %d" % peer)
	if multiplayer.is_server():
		_remove_from_random_queue(peer)
		_remove_from_crazy_queue(peer)
		_remove_from_private_room(peer, true)

func _on_server_disconnected():
	title_label.text = "Server Disconnected"
	info_label.text = "Disconnected from the server."

func start_client(host: String, port: int = 18361) -> void:
	print("Connecting to server %s:%d" % [host, port])
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(host, port)
	multiplayer.multiplayer_peer = peer
	multiplayer.connect("connected_to_server", _on_connected_to_server)
	multiplayer.connect("connection_failed", _on_connection_failed)
	multiplayer.connect("server_disconnected", _on_server_disconnected)
	$ClientUI.show()

func _on_connected_to_server():
	title_label.text = "Connected"
	info_label.text = "Requesting a match..."
	var peer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	peer.get_peer(1).set_timeout(32, 180000, 300000)
	_request_selected_matchmaking()

func _on_connection_failed():
	title_label.text = "Connection Failed"
	info_label.text = "Failed to connect to the server."

func _request_selected_matchmaking() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		return

	title_label.text = "Waiting for opponent..."
	match matchmaking_mode:
		Utils.MatchmakingMode.PRIVATE_NORMAL_CREATE:
			info_label.text = "Creating normal private room..."
			request_create_private_room.rpc()
		Utils.MatchmakingMode.PRIVATE_CRAZY_CREATE:
			info_label.text = "Creating crazy private room..."
			request_create_private_room.rpc()
		Utils.MatchmakingMode.PRIVATE_JOIN:
			info_label.text = "Joining private room..."
			request_join_private_room.rpc(pending_room_code)
		Utils.MatchmakingMode.RANDOM_NORMAL:
			info_label.text = "In random normal queue"
			enter_random_regular_queue.rpc()
		Utils.MatchmakingMode.RANDOM_CRAZY:
			info_label.text = "In random crazy queue"
			enter_random_crazy_queue.rpc()
		Utils.MatchmakingMode.AI_NORMAL:
			info_label.text = "Joining normal game against AI"
			enter_ai_normal_game.rpc()
		_:
			print("Unknown matchmaking mode: %d" % matchmaking_mode)
	$ClientUI.show()

@rpc("any_peer")
func enter_random_regular_queue():
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_remove_from_private_room(sender_id, false)
	if regular_queue.has(sender_id):
		return
	regular_queue.append(sender_id)
	_try_match_random_queue()

@rpc("any_peer")
func enter_random_crazy_queue():
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_remove_from_private_room(sender_id, false)
	if crazy_queue.has(sender_id):
		return
	crazy_queue.append(sender_id)
	_try_match_crazy_queue()
	
@rpc("any_peer")
func enter_ai_normal_game():
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_remove_from_private_room(sender_id, false)
	_start_game_for_peers([1, sender_id], true)

@rpc("any_peer")
func request_create_private_room():
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_remove_from_random_queue(sender_id)
	_remove_from_private_room(sender_id, false)

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
	_remove_from_crazy_queue(sender_id)

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
	# FIXME: set appropriate type not just normal game
	_start_game_for_peers([host_id, sender_id], false)

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
	_remove_from_crazy_queue(sender_id)

@rpc("authority", "call_remote", "reliable")
func private_room_created(code: String):
	print("Private room created: %s" % code)
	title_label.text = "Waiting for opponent..."
	info_label.text = "Room code: %s" % code
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
func send_to_game(slot: int, peers: Array, crazy: bool):
	var container = games.get_node("GameContainer%s/SubViewportContainer" % slot)
	container.visible = true
	var game = container.get_node("SubViewport/Game")
	game.crazy = crazy
	game.visible = true
	game.connected_peers = peers
	var camera = game.get_node("CameraPivot/Camera3D")
	camera.make_current()
	$ClientUI/VBoxContainer/TitleLabel.text = "In game"
	$ClientUI/VBoxContainer/InfoLabel.text = "Currently playing a game"

func _try_match_random_queue() -> void:
	while regular_queue.size() >= 2:
		var first = regular_queue.pop_front()
		var second = regular_queue.pop_front()
		_start_game_for_peers([first, second], false)
		
func _try_match_crazy_queue() -> void:
	while crazy_queue.size() >= 2:
		var first = crazy_queue.pop_front()
		var second = crazy_queue.pop_front()
		_start_game_for_peers([first, second], true)

func _start_game_for_peers(peers: Array, is_crazy: bool) -> void:
	var game
	if is_crazy:
		game = spawn_new_crazy_game()
	else:
		game = spawn_new_regular_game()
	for peer_id in peers:
		send_to_game.rpc_id(int(peer_id), game.lobby_slot, peers, is_crazy)
	game.connected_peers = peers
	game.start_game()

func _remove_from_random_queue(peer_id: int) -> void:
	while regular_queue.has(peer_id):
		regular_queue.erase(peer_id)

func _remove_from_crazy_queue(peer_id: int) -> void:
	while crazy_queue.has(peer_id):
		crazy_queue.erase(peer_id)
		
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

func spawn_new_regular_game() -> Node:
	var spot = free_spots[0]
	free_spots.remove_at(0)

	var isolated: Node3D = isolated_game.instantiate()
	isolated.name = "GameContainer%s" % spot
	var game = isolated.get_node("SubViewportContainer/SubViewport/Game")
	regular_games[spot] = game
	game.lobby_slot = spot
	game.crazy = false
	games.add_child(isolated)

	print("putting game in spot " + str(spot))
	if free_spots.size() == 0:
		free_spots.append(spot + 1)
	return game
	
func spawn_new_crazy_game() -> Node:
	var spot = free_spots[0]
	free_spots.remove_at(0)

	var isolated: Node3D = isolated_game.instantiate()
	isolated.name = "GameContainer%s" % spot
	var game = isolated.get_node("SubViewportContainer/SubViewport/Game")
	crazy_games[spot] = game
	game.lobby_slot = spot
	game.crazy = true
	games.add_child(isolated)

	print("putting CRAZY game in spot " + str(spot))
	if free_spots.size() == 0:
		free_spots.append(spot + 1)
	return game

func despawn_game_at(spot: int):
	var game = regular_games[spot]
	var fs_pos = free_spots.bsearch(spot)
	free_spots.insert(fs_pos, spot)
	games.remove_child(game)
	game.queue_free()
