extends Node3D

var free_spots = [0]
var regular_games = {}

var regular_queue = []

var init_mp = null
var init_slot = null
var init_peers = null

var player_tokens: Dictionary[int, String] = {}
var player_info: Dictionary[int, Dictionary] = {}

@onready var games = $Games
const lobby_scene = preload("res://Scenes/mp_lobby.tscn")
const reg_game_scene = preload("res://main.tscn")
const isolated_game = preload("res://Scenes/isolated_game.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
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
func _process(delta: float) -> void:
	pass
	
func start_server(port: int = 18361) -> void:
	print("Starting server on port %d" % port)
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
	var config := ConfigFile.new()
	if config.load("user://account.cfg") == OK:
		var token = config.get_value("account", "session", "")
		auth.rpc_id(1, token)
	enter_random_regular_queue.rpc()
	pass
	
func _on_connection_failed():
	pass
	
@rpc("any_peer")
func enter_random_regular_queue():
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	regular_queue.append(sender_id)
	if regular_queue.size() >= 2:
		var first = regular_queue.pop_front()
		var second = regular_queue.pop_front()
		var game = spawn_new_regular_game()
		send_to_game.rpc_id(first, game.lobby_slot, [first, second])
		send_to_game.rpc_id(second, game.lobby_slot, [first, second])
		game.connected_peers = [first, second]
		game.start_game()
		
@rpc("authority", "call_remote", "reliable")
func send_to_game(slot: int, peers: Array):
	var container = games.get_node("GameContainer%s/SubViewportContainer" % slot)
	container.visible = true
	var game = container.get_node("SubViewport/Game")
	game.visible = true
	var camera = game.get_node("CameraPivot/Camera3D")
	camera.make_current()

@rpc("any_peer", "call_remote", "reliable")
func auth(token: String):
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	player_tokens[sender_id] = token
	if token != "":
		print("got token from peer %d" % sender_id)
		var info = await $BackendRequests.info_for_account(token)
		player_info[sender_id] = info
		print("got player info for peer %d: %s" % [sender_id, str(info)])

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

func despawn_game_at(spot: int):
	var game = regular_games[spot]
	var fs_pos = free_spots.bsearch(spot)
	free_spots.insert(fs_pos, spot)
	games.remove_child(game)
	game.queue_free()
