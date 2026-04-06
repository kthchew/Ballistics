extends Node3D

@onready var randPoolButton = $MainMenu/MenuUI/BottomButtons/RandomPoolButton
@onready var randCrazyButton = $MainMenu/MenuUI/BottomButtons/RandomCrazyPoolButton
@onready var crazy = false

@onready var priv_button = $MainMenu/MenuUI/BottomButtons/PrivateGameButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var args := OS.get_cmdline_args()
	for a in args:
		if a == "--server":
			get_tree().call_deferred("change_scene_to_file", "res://Scenes/mp_lobby.tscn")
			
	randPoolButton.pressed.connect(_on_Rpool_pressed)
	randCrazyButton.pressed.connect(_on_Cpool_pressed)
		priv_button.pressed.connect(_on_priv_pressed)

func exit():
	$OverheadLight/Light/AudioStreamPlayer3D.play()
	await get_tree().create_timer(0.25).timeout
	$OverheadLight/Light.light_energy = 0
	$MainMenu.hide()
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://Scenes/mp_lobby.tscn")
	
func _on_priv_pressed():
	$MainMenu/MenuUI/PrivateGamePanel.show()
	
func _on_Rpool_pressed():
	get_tree().set_meta("crazy", false)
	exit()

func _on_Cpool_pressed():
	get_tree().set_meta("crazy", true)
	exit()
