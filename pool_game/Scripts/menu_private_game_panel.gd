extends Panel

@onready var pool_btn := $HBoxContainer/CreateGameContainer/PoolButton
@onready var crazy_btn := $HBoxContainer/CreateGameContainer/CrazyPoolButton
@onready var knockout_btn := $HBoxContainer/CreateGameContainer/KnockoutButton

@onready var join_code_input := $HBoxContainer/JoinGameContainer/RoomCodeInput
@onready var join_btn := $HBoxContainer/JoinGameContainer/JoinRoomButton

@onready var close_btn := $CloseButton

const mp_lobby_scene: PackedScene = preload("res://Scenes/mp_lobby.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pool_btn.pressed.connect(_on_pool_create)
	crazy_btn.pressed.connect(_on_crazy_create)
	knockout_btn.pressed.connect(_on_knockout_create)
	join_btn.pressed.connect(_on_join)
	close_btn.pressed.connect(_on_close)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func _on_pool_create() -> void:
	var lobby := mp_lobby_scene.instantiate()
	lobby.matchmaking_mode = Utils.MatchmakingMode.PRIVATE_CREATE
	get_tree().change_scene_to_node(lobby)
	
func _on_crazy_create() -> void:
	pass
	
func _on_knockout_create() -> void:
	pass

func _on_join() -> void:
	var code: String = join_code_input.text
	if code == "":
		return
	var lobby := mp_lobby_scene.instantiate()
	lobby.matchmaking_mode = Utils.MatchmakingMode.PRIVATE_JOIN
	lobby.pending_room_code = code
	get_tree().change_scene_to_node(lobby)
	
func _on_close() -> void:
	hide()
