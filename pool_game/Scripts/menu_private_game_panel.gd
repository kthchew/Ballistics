extends Panel

@onready var pool_btn := $HBoxContainer/CreateGameContainer/PoolButton
@onready var crazy_btn := $HBoxContainer/CreateGameContainer/CrazyPoolButton
@onready var knockout_btn := $HBoxContainer/CreateGameContainer/KnockoutButton

@onready var join_code_input = $HBoxContainer/JoinGameContainer/RoomCodeInput
@onready var join_btn := $HBoxContainer/JoinGameContainer/JoinRoomButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pool_btn.pressed.connect(_on_pool_create)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func _on_pool_create() -> void:
	pass
	
func _on_crazy_create() -> void:
	pass
	
func _on_knockout_create() -> void:
	pass

func _on_join() -> void:
	pass
