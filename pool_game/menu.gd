extends Node3D

@onready var randPoolButton = $MainMenu/MenuUI/BottomButtons/RandomPoolButton
@onready var resume_button = $MainMenu/MenuUI/BottomButtons/ResumeGameButton

@onready var priv_button = $MainMenu/MenuUI/BottomButtons/PrivateGameButton
@onready var backend_requests = $MainMenu/MenuUI/AccountScreen/BackendRequests

const mp_lobby_scene: PackedScene = preload("res://Scenes/mp_lobby.tscn")

var resumable_game_id: String = ""

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var args := OS.get_cmdline_args()
	for a in args:
		if a == "--server":
			get_tree().change_scene_to_file("res://Scenes/mp_lobby.tscn")
			
	randPoolButton.pressed.connect(_on_Rpool_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	priv_button.pressed.connect(_on_priv_pressed)
	await _refresh_resume_button_state()

func _refresh_resume_button_state() -> void:
	resume_button.disabled = true
	resumable_game_id = ""

	var config := ConfigFile.new()
	if config.load("user://account.cfg") != OK:
		return

	var token: String = str(config.get_value("account", "session", ""))
	if token == "":
		return

	var account_info: Dictionary = await backend_requests.info_for_account(token)
	if not account_info.has("current_game_id"):
		return

	var game_id := str(account_info["current_game_id"])
	if game_id == "":
		return

	resumable_game_id = game_id
	resume_button.disabled = false

func _on_Rpool_pressed():
	$OverheadLight/Light/AudioStreamPlayer3D.play()
	await get_tree().create_timer(0.25).timeout
	$OverheadLight/Light.light_energy = 0
	$MainMenu.hide()
	await get_tree().create_timer(0.5).timeout
	var lobby := mp_lobby_scene.instantiate()
	lobby.matchmaking_mode = Utils.MatchmakingMode.RANDOM
	get_tree().change_scene_to_node(lobby)

func _on_resume_pressed() -> void:
	if resumable_game_id == "":
		return
	var lobby := mp_lobby_scene.instantiate()
	lobby.matchmaking_mode = Utils.MatchmakingMode.RESUME
	lobby.resume_game_id = resumable_game_id
	get_tree().change_scene_to_node(lobby)
	
func _on_priv_pressed():
	$MainMenu/MenuUI/PrivateGamePanel.show()
