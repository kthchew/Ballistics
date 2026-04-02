extends Node3D

@onready var randPoolButton = $MainMenu/MenuUI/BottomButtons/RandomPoolButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var args := OS.get_cmdline_args()
	for a in args:
		if a == "--server":
			get_tree().change_scene_to_file("res://Scenes/mp_lobby.tscn")
			
	randPoolButton.pressed.connect(_on_Rpool_pressed)

func _on_Rpool_pressed():
	$OverheadLight/Light/AudioStreamPlayer3D.play()
	await get_tree().create_timer(0.25).timeout
	$OverheadLight/Light.light_energy = 0
	$MainMenu.hide()
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://Scenes/mp_lobby.tscn")
