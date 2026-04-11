extends Control

const MP_LOBBY_SCENE: PackedScene = preload("res://Scenes/mp_lobby.tscn")

var friends: Array = []
var friend_requests: Array = []
var game_invites: Array = []
var is_refreshing_lists := false
var poll_timer: Timer

var keyboard_dodge_tween: Tween

@onready var backend := $BackendRequests
@onready var auth_panel := $AuthPanel
@onready var logged_in_panel := $LoggedInPanel

@onready var username_input := $AuthPanel/UsernameInput
@onready var password_input := $AuthPanel/PasswordInput
@onready var login_option_button := $AuthPanel/ModeButtons/LoginOptionButton
@onready var register_option_button := $AuthPanel/ModeButtons/RegisterOptionButton
@onready var auth_status_label := $AuthPanel/AuthStatusLabel

@onready var username_label := $LoggedInPanel/Content/Header/UsernameLabel
@onready var friends_list := $LoggedInPanel/Content/FriendsList
@onready var add_friend_input := $LoggedInPanel/Content/FriendsListHeader/FriendActions/AddFriendInput
@onready var friend_requests_list := $LoggedInPanel/Content/RequestsRow/FriendRequests/FriendRequestsList
@onready var game_invites_list := $LoggedInPanel/Content/RequestsRow/GameInvites/GameInvitesList
@onready var status_label := $LoggedInPanel/Content/StatusLabel

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$AuthPanel/AuthActions/ConfirmButton.pressed.connect(_on_confirm_pressed)
	$AuthPanel/AuthActions/CloseButton.pressed.connect(_on_close_pressed)

	poll_timer = Timer.new()
	poll_timer.wait_time = 5.0
	poll_timer.one_shot = false
	poll_timer.autostart = false
	add_child(poll_timer)
	poll_timer.timeout.connect(_on_poll_timeout)

	_refresh_session_view()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if visible:
			_refresh_session_view()
		else:
			if poll_timer != null:
				poll_timer.stop()

func _process(delta: float) -> void:
	# https://forum.godotengine.org/t/virtual-keyboard-covering-lineedit/66623/5
	if auth_panel.visible and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		if DisplayServer.virtual_keyboard_get_height() > 0:
			move_to_position(Vector2(0, -DisplayServer.virtual_keyboard_get_height() / 2.0))
		else:
			move_to_position(Vector2.ZERO)

func move_to_position(new_position: Vector2, duration: float = 0.1) -> void:
	if keyboard_dodge_tween != null and keyboard_dodge_tween.is_valid():
		keyboard_dodge_tween.stop_all()
	else:
		keyboard_dodge_tween = create_tween()
	keyboard_dodge_tween.tween_property(self, "position", new_position, duration)

func _refresh_session_view() -> void:
	var session_state: Dictionary = await backend.get_session_state()
	var is_logged_in := bool(session_state.get("logged_in", false))
	if is_logged_in:
		_show_logged_in(str(session_state.get("username", "")))
		if poll_timer != null and poll_timer.is_stopped():
			poll_timer.start()
		await _refresh_lists()
	else:
		_show_auth()

func _show_auth() -> void:
	auth_panel.show()
	logged_in_panel.hide()
	if poll_timer != null:
		poll_timer.stop()
	auth_status_label.text = ""
	status_label.text = ""

func _show_logged_in(username: String) -> void:
	auth_panel.hide()
	logged_in_panel.show()
	username_label.text = username

func _refresh_lists() -> void:
	if is_refreshing_lists:
		return
	is_refreshing_lists = true
	friends = await backend.get_friends()
	friend_requests = await backend.get_friend_requests()
	game_invites = await backend.get_game_invites()
	_populate_friends_list()
	_populate_friend_requests_list()
	_populate_game_invites_list()
	is_refreshing_lists = false

func _on_poll_timeout() -> void:
	if not visible or not logged_in_panel.visible:
		return
	await _refresh_lists()
	
func _get_selected_items_text(list: ItemList) -> Array:
	var selected_indexes = list.get_selected_items()
	var selected_texts = []
	for idx in selected_indexes:
		if idx >= 0 and idx < list.get_item_count():
			selected_texts.append(list.get_item_text(idx))
	return selected_texts
	
func _select_items_by_text(list: ItemList, texts: Array) -> void:
	for i in range(list.get_item_count()):
		if list.get_item_text(i) in texts:
			list.select(i)

func _populate_friends_list() -> void:
	var selected: Array = _get_selected_items_text(friends_list)
	
	friends_list.clear()
	for friend in friends:
		friends_list.add_item(str(friend))
		
	_select_items_by_text(friends_list, selected)

func _populate_friend_requests_list() -> void:
	var selected: Array = _get_selected_items_text(friend_requests_list)
	
	friend_requests_list.clear()
	for request in friend_requests:
		friend_requests_list.add_item("Friend Request: %s" % str(request.get("from_user", "")))
		
	_select_items_by_text(friend_requests_list, selected)

func _populate_game_invites_list() -> void:
	var selected: Array = _get_selected_items_text(game_invites_list)
	
	game_invites_list.clear()
	for invite in game_invites:
		var from_user := str(invite.get("from_user", ""))
		game_invites_list.add_item("Invite: %s" % from_user)
	
	_select_items_by_text(game_invites_list, selected)

func _response_text(response: Dictionary, fallback: String) -> String:
	if "result" in response:
		var body := str(response["result"]).strip_edges()
		if body != "":
			return body
	if "error" in response:
		return str(response["error"])
	return fallback

func _selected_friend() -> String:
	var selected: PackedInt32Array = friends_list.get_selected_items()
	if selected.is_empty():
		return ""
	var idx := int(selected[0])
	if idx < 0 or idx >= friends.size():
		return ""
	return str(friends[idx])

func _selected_friend_request() -> Dictionary:
	var selected: PackedInt32Array = friend_requests_list.get_selected_items()
	if selected.is_empty():
		return {}
	var idx := int(selected[0])
	if idx < 0 or idx >= friend_requests.size():
		return {}
	return friend_requests[idx]

func _selected_game_invite() -> Dictionary:
	var selected: PackedInt32Array = game_invites_list.get_selected_items()
	if selected.is_empty():
		return {}
	var idx := int(selected[0])
	if idx < 0 or idx >= game_invites.size():
		return {}
	return game_invites[idx]

func _generate_room_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var parts: Array = []
	for i in range(3):
		var chunk := ""
		for j in range(4):
			chunk += alphabet[rng.randi_range(0, alphabet.length() - 1)]
		parts.append(chunk)
	return "%s-%s-%s" % [parts[0], parts[1], parts[2]]
	
func _on_confirm_pressed() -> void:
	var username: String = username_input.text.strip_edges()
	var password: String = password_input.text
	if username == "" or password == "":
		auth_status_label.text = "Username and password are required."
		return

	var response: Dictionary
	if login_option_button.button_pressed:
		response = await backend.login(username, password)
	else:
		response = await backend.register(username, password)

	var code := int(response.get("response_code", 0))
	if code == 200 or code == 201:
		auth_status_label.text = ""
		await _refresh_session_view()
		return
	auth_status_label.text = _response_text(response, "Authentication failed.")

func _on_refresh_pressed() -> void:
	await _refresh_lists()
	status_label.text = "Refreshed."

func _on_logout_pressed() -> void:
	await backend.logout()
	friends = []
	friend_requests = []
	game_invites = []
	_show_auth()
	password_input.text = ""

func _on_add_friend_pressed() -> void:
	var to_user: String = add_friend_input.text.strip_edges()
	if to_user == "":
		status_label.text = "Enter a username to send a friend request."
		return
	var response: Dictionary = await backend.send_friend_request(to_user)
	if int(response.get("response_code", 0)) == 200:
		status_label.text = "Friend request sent to %s." % to_user
		add_friend_input.text = ""
	else:
		status_label.text = _response_text(response, "Could not send friend request.")

func _on_invite_friend_standard_pressed() -> void:
	_invite_friend(Utils.MatchmakingMode.PRIVATE_NORMAL_CREATE)

func _on_invite_friend_crazy_pressed() -> void:
	_invite_friend(Utils.MatchmakingMode.PRIVATE_CRAZY_CREATE)

func _invite_friend(matchmaking_mode: Utils.MatchmakingMode) -> void:
	var friend_username := _selected_friend()
	if friend_username == "":
		status_label.text = "Select a friend to invite."
		return

	var room_code := _generate_room_code()
	var lobby := MP_LOBBY_SCENE.instantiate()
	lobby.matchmaking_mode = matchmaking_mode
	lobby.pending_room_code = room_code
	lobby.suppress_private_room_code_display = true
	lobby.created_via_friends_menu = true
	lobby.friend_invite_target = friend_username
	get_tree().change_scene_to_node(lobby)

func _on_accept_friend_request_pressed() -> void:
	var request := _selected_friend_request()
	if request.is_empty():
		status_label.text = "Select a friend request first."
		return
	var from_user := str(request.get("from_user", ""))
	var response: Dictionary = await backend.accept_friend_request(from_user)
	if int(response.get("response_code", 0)) == 200:
		status_label.text = "Friend request accepted."
		await _refresh_lists()
	else:
		status_label.text = _response_text(response, "Failed to accept friend request.")

func _on_reject_friend_request_pressed() -> void:
	var request := _selected_friend_request()
	if request.is_empty():
		status_label.text = "Select a friend request first."
		return
	var from_user := str(request.get("from_user", ""))
	var response: Dictionary = await backend.reject_friend_request(from_user)
	if int(response.get("response_code", 0)) == 200:
		status_label.text = "Friend request rejected."
		await _refresh_lists()
	else:
		status_label.text = _response_text(response, "Failed to reject friend request.")

func _on_accept_game_invite_pressed() -> void:
	var invite := _selected_game_invite()
	if invite.is_empty():
		status_label.text = "Select a game invite first."
		return

	var from_user := str(invite.get("from_user", ""))
	var room_code := str(invite.get("room_code", ""))

	var lobby := MP_LOBBY_SCENE.instantiate()
	lobby.matchmaking_mode = Utils.MatchmakingMode.PRIVATE_JOIN
	lobby.pending_room_code = room_code
	lobby.suppress_private_room_code_display = true
	lobby.joined_via_friend_invite = true
	lobby.pending_friend_invite_from_user = from_user
	get_tree().change_scene_to_node(lobby)

func _on_dismiss_game_invite_pressed() -> void:
	var invite := _selected_game_invite()
	if invite.is_empty():
		status_label.text = "Select a game invite first."
		return
	var from_user := str(invite.get("from_user", ""))
	var room_code := str(invite.get("room_code", ""))
	var response: Dictionary = await backend.remove_game_invite(from_user, room_code)
	if int(response.get("response_code", 0)) == 200:
		status_label.text = "Invite dismissed."
		await _refresh_lists()
	else:
		status_label.text = _response_text(response, "Failed to dismiss invite.")
	
func _on_close_pressed() -> void:
	visible = false
