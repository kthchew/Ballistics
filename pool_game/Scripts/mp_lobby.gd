extends Node3D

signal private_room_code_ready(code: String)
signal private_room_error(message: String)
signal private_room_closed_notice(reason: String)

var free_spots = [0]
var regular_games = {}
var regular_queue = []
var crazy_queue = []
var crazy_games = {}
var single_player_games = {}
var private_rooms = {}
var room_by_peer = {}

var init_mp = null
var init_slot = null
var init_peers = null

var config := ConfigFile.new()
const CONFIG_PATH := "user://settings.cfg"
const FRIEND_JOIN_RETRY_MAX := 3
const TLS_CERT_RELOAD_INTERVAL_SEC := 30.0 * 60.0
const TLS_ROTATION_WAIT_PERIOD_SEC := 15.0 * 60.0
const TLS_MAINTENANCE_MESSAGE := "Server is in maintenance. Matchmaking is temporarily unavailable."

@export var matchmaking_mode = Utils.MatchmakingMode.RANDOM_NORMAL
@export var pending_room_code := ""
@export var suppress_private_room_code_display := false
@export var created_via_friends_menu := false
@export var friend_invite_target := ""
@export var joined_via_friend_invite := false
@export var pending_friend_invite_from_user := ""

var friend_invite_sent := false
var friend_invite_room_code := ""
var friend_join_retry_count := 0

var tls_cert_dir := ""
var tls_hostname := ""
var tls_cert_path := ""
var tls_key_path := ""
var tls_cert_mtime := -1
var tls_key_mtime := -1
var tls_rotation_in_progress := false
var tls_wait_period_active := false
var server_port := 18361

@onready var tls_reload_timer: Timer = Timer.new()
@onready var tls_wait_timer: Timer = Timer.new()

@onready var games = $Games
const lobby_scene = preload("res://Scenes/mp_lobby.tscn")
const reg_game_scene = preload("res://Scenes/main.tscn")
const isolated_game = preload("res://Scenes/isolated_game.tscn")

@onready var backend_requests = $BackendRequests
@onready var title_label = $ClientUI/VBoxContainer/TitleLabel
@onready var info_label = $ClientUI/VBoxContainer/InfoLabel
@onready var exit_button = $ClientUI/VBoxContainer/ExitButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	exit_button.pressed.connect(_on_exit_clicked)
	tls_reload_timer.wait_time = TLS_CERT_RELOAD_INTERVAL_SEC
	tls_reload_timer.one_shot = false
	tls_reload_timer.autostart = false
	tls_reload_timer.timeout.connect(_on_tls_reload_timer_timeout)
	add_child(tls_reload_timer)
	tls_wait_timer.wait_time = TLS_ROTATION_WAIT_PERIOD_SEC
	tls_wait_timer.one_shot = true
	tls_wait_timer.autostart = false
	tls_wait_timer.timeout.connect(_on_tls_wait_timer_timeout)
	add_child(tls_wait_timer)
	
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
		var default := Constants.DEFAULT_GAME_SERVER_ADDRESS_DEV if OS.is_debug_build() else Constants.DEFAULT_GAME_SERVER_ADDRESS
		start_client(default if remote_addr == "" else remote_addr, remote_port)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
	
func _on_exit_clicked() -> void:
	await _cancel_pending_friend_invite_if_needed()
	request_leave_matchmaking.rpc_id(1)
	get_tree().change_scene_to_file("res://Scenes/Menu.tscn")

func _response_text(response: Dictionary, fallback: String) -> String:
	if "result" in response:
		var body := str(response["result"]).strip_edges()
		if body != "":
			return body
	if "error" in response:
		return str(response["error"])
	return fallback

func _cancel_pending_friend_invite_if_needed() -> void:
	if not created_via_friends_menu:
		return
	if not friend_invite_sent:
		return
	if friend_invite_target.strip_edges().is_empty() or friend_invite_room_code.strip_edges().is_empty():
		return
	await backend_requests.cancel_game_invite(friend_invite_target, friend_invite_room_code)
	friend_invite_sent = false

func _send_friend_invite_after_room_created(code: String) -> void:
	if not created_via_friends_menu:
		return
	if friend_invite_target.strip_edges().is_empty():
		info_label.text = "No friend selected for invite."
		return
	if friend_invite_sent:
		return
		
	var response: Dictionary = await backend_requests.send_game_invite(friend_invite_target, code)
	if int(response.get("response_code", 0)) == 200:
		friend_invite_sent = true
		friend_invite_room_code = code
		info_label.text = "Invite sent to %s. Waiting for friend..." % friend_invite_target
		return
	info_label.text = _response_text(response, "Failed to send friend invite.")

# TODO: do this from the server side so that a disconnected or crashed client won't cause the invite to be left behind
func _consume_joined_friend_invite_if_needed() -> void:
	if not joined_via_friend_invite:
		return
	if pending_friend_invite_from_user.strip_edges().is_empty() or pending_room_code.strip_edges().is_empty():
		return
	await backend_requests.remove_game_invite(pending_friend_invite_from_user, pending_room_code)

func _retry_or_expire_friend_join(reason: String) -> bool:
	if not joined_via_friend_invite:
		return false
	var lowered := reason.to_lower()
	if lowered.find("not found") == -1:
		return false
	if friend_join_retry_count < FRIEND_JOIN_RETRY_MAX:
		friend_join_retry_count += 1
		info_label.text = "Invite not ready yet. Retrying (%d/%d)..." % [friend_join_retry_count, FRIEND_JOIN_RETRY_MAX]
		await get_tree().create_timer(1.0).timeout
		request_join_private_room.rpc(pending_room_code)
		return true
	await _consume_joined_friend_invite_if_needed()
	info_label.text = "Invite expired or host left."
	return true

func queue_random_match() -> void:
	matchmaking_mode = Utils.MatchmakingMode.RANDOM_NORMAL
	pending_room_code = ""
	_request_selected_matchmaking()

func create_private_room(mode: Utils.MatchmakingMode = Utils.MatchmakingMode.PRIVATE_NORMAL_CREATE) -> void:
	matchmaking_mode = mode
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
	server_port = port
	randomize()
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(port, 32)
	tls_hostname = _resolve_server_tls_hostname()
	if _apply_server_tls(peer, tls_hostname):
		tls_reload_timer.start()
	else:
		tls_reload_timer.stop()
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
	if title_label.text == "Server Maintenance":
		return
	title_label.text = "Server Disconnected"
	info_label.text = "Disconnected from the server."

func start_client(host: String, port: int = 18361) -> void:
	print("Connecting to server %s:%d" % [host, port])
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(host, port)
	_apply_client_tls(peer, host)
	multiplayer.multiplayer_peer = peer
	multiplayer.connect("connected_to_server", _on_connected_to_server)
	multiplayer.connect("connection_failed", _on_connection_failed)
	multiplayer.connect("server_disconnected", _on_server_disconnected)
	$ClientUI.show()

func _resolve_cert_dir() -> String:
	var override_dir := OS.get_environment("BALLISTICS_CERT_DIR").strip_edges()
	if not override_dir.is_empty():
		return override_dir
	var home_dir := OS.get_environment("HOME").strip_edges()
	if home_dir.is_empty():
		return ""
	return home_dir.path_join("certs")

func _normalize_tls_hostname(raw_host: String) -> String:
	var host := raw_host.strip_edges()
	if host.begins_with("https://"):
		host = host.trim_prefix("https://")
	elif host.begins_with("http://"):
		host = host.trim_prefix("http://")

	if host.find("/") != -1:
		host = host.get_slice("/", 0)

	if host.begins_with("[") and host.ends_with("]"):
		host = host.substr(1, host.length() - 2)
	elif host.count(":") == 1:
		host = host.get_slice(":", 0)

	return host.strip_edges().to_lower()

func _resolve_server_tls_hostname() -> String:
	var env_hostname := _normalize_tls_hostname(OS.get_environment("BALLISTICS_SERVER_HOSTNAME"))
	if not env_hostname.is_empty():
		return env_hostname

	return "domain"

func _resolve_cert_paths(hostname: String) -> bool:
	var normalized_hostname := _normalize_tls_hostname(hostname)
	tls_cert_dir = _resolve_cert_dir()
	if tls_cert_dir.is_empty() or normalized_hostname.is_empty():
		return false
	tls_cert_path = tls_cert_dir.path_join("%s.crt" % normalized_hostname)
	tls_key_path = tls_cert_dir.path_join("%s.key" % normalized_hostname)
	return true

func _load_server_tls_options(hostname: String) -> TLSOptions:
	if not _resolve_cert_paths(hostname):
		push_warning("TLS disabled: missing certificate directory or hostname.")
		return null

	if not FileAccess.file_exists(tls_cert_path) or not FileAccess.file_exists(tls_key_path):
		push_warning("TLS disabled: missing cert or key at %s and %s" % [tls_cert_path, tls_key_path])
		return null

	var certificate := X509Certificate.new()
	if certificate.load(tls_cert_path) != OK:
		push_warning("TLS disabled: failed to load certificate %s" % tls_cert_path)
		return null

	var key := CryptoKey.new()
	if key.load(tls_key_path) != OK:
		push_warning("TLS disabled: failed to load key %s" % tls_key_path)
		return null

	tls_cert_mtime = int(FileAccess.get_modified_time(tls_cert_path))
	tls_key_mtime = int(FileAccess.get_modified_time(tls_key_path))
	return TLSOptions.server(key, certificate)

func _apply_server_tls(peer: ENetMultiplayerPeer, hostname: String) -> bool:
	var options := _load_server_tls_options(hostname)
	if options == null:
		return false

	var host_connection: ENetConnection = peer.get_host()
	if host_connection == null or not host_connection.has_method("dtls_server_setup"):
		push_warning("TLS disabled: ENet host does not support DTLS setup.")
		return false

	var err: int = host_connection.dtls_server_setup(options)
	if err != OK:
		push_warning("TLS disabled: DTLS server setup failed with error %d" % int(err))
		return false

	print("TLS enabled for hostname %s" % hostname)
	return true

func _apply_client_tls(peer: ENetMultiplayerPeer, host: String) -> void:
	var normalized_host := _normalize_tls_hostname(host)
	if normalized_host.is_empty():
		return
	# skip TLS for localhost because it would be annoying to set up TLS for dev environments
	if normalized_host == "localhost" or normalized_host == "127.0.0.1":
		return

	var host_connection: ENetConnection = peer.get_host()
	if host_connection == null or not host_connection.has_method("dtls_client_setup"):
		print("TLS warning: ENet host does not support DTLS client setup.")
		return

	var options := TLSOptions.client()
	var err: int = host_connection.dtls_client_setup(normalized_host, options)
	if err != OK:
		print("TLS warning: DTLS client setup failed with error %d" % int(err))

func _on_tls_reload_timer_timeout() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null:
		return
	_reload_server_tls_if_changed(peer)
	_try_finish_rotation_early()

func _reload_server_tls_if_changed(peer: ENetMultiplayerPeer) -> void:
	if tls_rotation_in_progress:
		return
	if tls_cert_path.is_empty() or tls_key_path.is_empty():
		return
	if not FileAccess.file_exists(tls_cert_path) or not FileAccess.file_exists(tls_key_path):
		return

	var cert_mtime := int(FileAccess.get_modified_time(tls_cert_path))
	var key_mtime := int(FileAccess.get_modified_time(tls_key_path))
	if cert_mtime == tls_cert_mtime and key_mtime == tls_key_mtime:
		return

	_begin_tls_rotation_wait_period()

func _begin_tls_rotation_wait_period() -> void:
	tls_rotation_in_progress = true
	tls_wait_period_active = true
	_kick_all_queued_players(TLS_MAINTENANCE_MESSAGE)

	if not _has_active_games():
		print("TLS rotation: no active games, rotating certificate immediately.")
		_rotate_server_peer_with_tls()
		_end_tls_rotation_wait_period()
		return

	print("TLS rotation: waiting up to %d seconds for games to finish." % int(TLS_ROTATION_WAIT_PERIOD_SEC))
	tls_wait_timer.start()

func _on_tls_wait_timer_timeout() -> void:
	if not tls_rotation_in_progress:
		return

	if _has_active_games():
		print("TLS rotation: wait period expired with active games. Forcing full restart.")
		_rotate_server_peer_with_tls()
	else:
		print("TLS rotation: games completed before timeout, rotating now.")
		_rotate_server_peer_with_tls()

	_end_tls_rotation_wait_period()

func _try_finish_rotation_early() -> void:
	if not tls_rotation_in_progress:
		return
	if not tls_wait_period_active:
		return
	if _has_active_games():
		return

	print("TLS rotation: all games finished during maintenance window, rotating now.")
	tls_wait_timer.stop()
	_rotate_server_peer_with_tls()
	_end_tls_rotation_wait_period()

func _has_active_games() -> bool:
	for game in regular_games.values():
		if is_instance_valid(game):
			return true
	for game in crazy_games.values():
		if is_instance_valid(game):
			return true
	for game in single_player_games.values():
		if is_instance_valid(game):
			return true
	return false

func _rotate_server_peer_with_tls() -> void:
	var old_peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if old_peer == null:
		push_warning("TLS rotation skipped: no active server peer.")
		return

	_kick_all_queued_players(TLS_MAINTENANCE_MESSAGE)

	clear_all_games()
	for peer_id in multiplayer.get_peers():
		maintenance_notice.rpc_id(int(peer_id), "Restarting server. Please reconnect in a few seconds.")
	await get_tree().create_timer(0.04).timeout
	for peer_id in multiplayer.get_peers():
		old_peer.disconnect_peer(int(peer_id))

	old_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var new_peer := ENetMultiplayerPeer.new()
	var create_err := new_peer.create_server(server_port, 32)
	if create_err != OK:
		push_error("TLS rotation failed: unable to create replacement server peer (%d)." % create_err)
		return

	if not _apply_server_tls(new_peer, tls_hostname):
		push_error("TLS rotation failed: unable to apply TLS to replacement peer.")
		new_peer.close()
		return

	multiplayer.multiplayer_peer = new_peer
	old_peer.close()
	print("TLS rotation complete: replacement peer is live on port %d." % server_port)

func _end_tls_rotation_wait_period() -> void:
	tls_wait_timer.stop()
	tls_rotation_in_progress = false
	tls_wait_period_active = false

func _kick_all_queued_players(reason: String) -> void:
	var notified := {}
	for peer_id in regular_queue:
		notified[int(peer_id)] = true
	for peer_id in crazy_queue:
		notified[int(peer_id)] = true
	for code in private_rooms.keys():
		var room: Dictionary = private_rooms[code]
		var host_id := int(room.get("host_id", 0))
		var guest_id := int(room.get("guest_id", 0))
		if host_id != 0:
			notified[host_id] = true
		if guest_id != 0:
			notified[guest_id] = true

	regular_queue.clear()
	crazy_queue.clear()
	private_rooms.clear()
	room_by_peer.clear()

	for peer_id in notified.keys():
		maintenance_notice.rpc_id(int(peer_id), reason)

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
			if pending_room_code.strip_edges().is_empty():
				request_create_private_room.rpc(Utils.GameType.EIGHT_BALL_MULTIPLAYER)
			else:
				request_create_private_room_with_code.rpc(pending_room_code, Utils.GameType.EIGHT_BALL_MULTIPLAYER)
		Utils.MatchmakingMode.PRIVATE_CRAZY_CREATE:
			info_label.text = "Creating crazy private room..."
			if pending_room_code.strip_edges().is_empty():
				request_create_private_room.rpc(Utils.GameType.CRAZY_EIGHT_BALL_MULTIPLAYER)
			else:
				request_create_private_room_with_code.rpc(pending_room_code, Utils.GameType.CRAZY_EIGHT_BALL_MULTIPLAYER)
		Utils.MatchmakingMode.PRIVATE_JOIN:
			info_label.text = "Joining private room..."
			request_join_private_room.rpc(pending_room_code)
		Utils.MatchmakingMode.RANDOM_NORMAL:
			info_label.text = "In random normal queue"
			enter_random_regular_queue.rpc()
		Utils.MatchmakingMode.RANDOM_CRAZY:
			info_label.text = "In random crazy queue"
			enter_random_crazy_queue.rpc()
		Utils.MatchmakingMode.SINGLE_PLAYER:
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
	if tls_wait_period_active:
		maintenance_notice.rpc_id(sender_id, TLS_MAINTENANCE_MESSAGE)
		return
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
	if tls_wait_period_active:
		maintenance_notice.rpc_id(sender_id, TLS_MAINTENANCE_MESSAGE)
		return
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
	if tls_wait_period_active:
		maintenance_notice.rpc_id(sender_id, TLS_MAINTENANCE_MESSAGE)
		return
	_remove_from_private_room(sender_id, false)
	_start_game_for_peers([1, sender_id], Utils.GameType.EIGHT_BALL_SINGLEPLAYER)

@rpc("any_peer")
func request_create_private_room(game_type: Utils.GameType):
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if tls_wait_period_active:
		maintenance_notice.rpc_id(sender_id, TLS_MAINTENANCE_MESSAGE)
		return
	_remove_from_random_queue(sender_id)
	_remove_from_crazy_queue(sender_id)
	_remove_from_private_room(sender_id, false)

	var code := _generate_unique_room_code()
	private_rooms[code] = {"host_id": sender_id, "guest_id": 0, "game_type": game_type}
	room_by_peer[sender_id] = code
	private_room_created.rpc_id(sender_id, code)

@rpc("any_peer")
func request_create_private_room_with_code(requested_code: String, game_type: Utils.GameType):
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if tls_wait_period_active:
		maintenance_notice.rpc_id(sender_id, TLS_MAINTENANCE_MESSAGE)
		return
	var code := _normalize_room_code(requested_code)
	_remove_from_random_queue(sender_id)
	_remove_from_private_room(sender_id, false)
	_remove_from_crazy_queue(sender_id)

	if code.is_empty():
		private_room_join_failed.rpc_id(sender_id, "Room code is empty.")
		return
	if private_rooms.has(code):
		private_room_join_failed.rpc_id(sender_id, "Room code already in use.")
		return

	private_rooms[code] = {"host_id": sender_id, "guest_id": 0, "game_type": game_type}
	room_by_peer[sender_id] = code
	private_room_created.rpc_id(sender_id, code)

@rpc("any_peer")
func request_join_private_room(code: String):
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if tls_wait_period_active:
		maintenance_notice.rpc_id(sender_id, TLS_MAINTENANCE_MESSAGE)
		return
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

	var room_game_type: Utils.GameType = room.get("game_type", Utils.GameType.EIGHT_BALL_MULTIPLAYER)

	room["guest_id"] = sender_id
	private_rooms[normalized_code] = room
	room_by_peer[sender_id] = normalized_code
	private_room_joined.rpc_id(host_id, normalized_code)
	private_room_joined.rpc_id(sender_id, normalized_code)

	private_rooms.erase(normalized_code)
	room_by_peer.erase(host_id)
	room_by_peer.erase(sender_id)
	_start_game_for_peers([host_id, sender_id], room_game_type)

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
	if suppress_private_room_code_display:
		title_label.text = "Waiting for opponent..."
		info_label.text = "Creating invite..."
	else:
		title_label.text = "Waiting for opponent..."
		info_label.text = "Room code: %s" % code
	await _send_friend_invite_after_room_created(code)
	emit_signal("private_room_code_ready", code)

@rpc("authority", "call_remote", "reliable")
func private_room_joined(code: String):
	print("Joined room: %s" % code)
	if created_via_friends_menu and code == friend_invite_room_code:
		friend_invite_sent = false
	if joined_via_friend_invite:
		await _consume_joined_friend_invite_if_needed()

@rpc("authority", "call_remote", "reliable")
func private_room_join_failed(reason: String):
	print("Private room join failed: %s" % reason)
	if await _retry_or_expire_friend_join(reason):
		return
	info_label.text = "Private room join failed: %s" % reason
	emit_signal("private_room_error", reason)

@rpc("authority", "call_remote", "reliable")
func private_room_closed(reason: String):
	print("Private room closed: %s" % reason)
	emit_signal("private_room_closed_notice", reason)

@rpc("authority", "call_remote", "reliable")
func maintenance_notice(message: String):
	title_label.text = "Server Maintenance"
	info_label.text = message

@rpc("authority", "call_remote", "reliable")
func send_to_game(slot: int, peers: Array, game_type: Utils.GameType):
	var container = games.get_node("GameContainer%s/SubViewportContainer" % slot)
	container.visible = true
	var game = container.get_node("SubViewport/Game")
	game.game_type = game_type
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
		_start_game_for_peers([first, second], Utils.GameType.EIGHT_BALL_MULTIPLAYER)
		
func _try_match_crazy_queue() -> void:
	while crazy_queue.size() >= 2:
		var first = crazy_queue.pop_front()
		var second = crazy_queue.pop_front()
		_start_game_for_peers([first, second], Utils.GameType.CRAZY_EIGHT_BALL_MULTIPLAYER)

func _start_game_for_peers(peers: Array, game_type: Utils.GameType) -> void:
	var game = _spawn_new_game(game_type)
	for peer_id in peers:
		if peer_id == 1:
			continue
		send_to_game.rpc_id(int(peer_id), game.lobby_slot, peers, game_type)
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

func _spawn_new_game(game_type: Utils.GameType) -> Node:
	var spot = free_spots[0]
	free_spots.remove_at(0)

	var isolated: Node3D = isolated_game.instantiate()
	isolated.name = "GameContainer%s" % spot
	var game = isolated.get_node("SubViewportContainer/SubViewport/Game")
	if game_type == Utils.GameType.CRAZY_EIGHT_BALL_MULTIPLAYER:
		crazy_games[spot] = game
	elif game_type == Utils.GameType.EIGHT_BALL_SINGLEPLAYER:
		single_player_games[spot] = game
	else:
		regular_games[spot] = game
	game.lobby_slot = spot
	game.game_type = game_type
	games.add_child(isolated)

	print("putting game in spot " + str(spot) + " type " + str(game_type))
	if free_spots.size() == 0:
		free_spots.append(spot + 1)
	return game
	
func spawn_new_regular_game() -> Node:
	return _spawn_new_game(Utils.GameType.EIGHT_BALL_MULTIPLAYER)
	
func spawn_new_crazy_game() -> Node:
	return _spawn_new_game(Utils.GameType.CRAZY_EIGHT_BALL_MULTIPLAYER)
	
func spawn_new_single_player_game() -> Node:
	return _spawn_new_game(Utils.GameType.EIGHT_BALL_SINGLEPLAYER)

func despawn_game_at(spot: int):
	var game = regular_games[spot]
	var fs_pos = free_spots.bsearch(spot)
	free_spots.insert(fs_pos, spot)
	games.remove_child(game)
	game.queue_free()

func clear_all_games():
	for spot in regular_games.keys():
		despawn_game_at(spot)
	for spot in crazy_games.keys():
		despawn_game_at(spot)
	for spot in single_player_games.keys():
		despawn_game_at(spot)
