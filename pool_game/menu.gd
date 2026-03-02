extends Node3D

@onready var randPoolButton = $MainMenu/MenuUI/BottomButtons/RandomPoolButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if "--train" in OS.get_cmdline_user_args() or "--train=true" in OS.get_cmdline_args():
		get_tree().change_scene_to_file("res://train.tscn")
		return
	randPoolButton.pressed.connect(_on_Rpool_pressed)

func _on_Rpool_pressed():
	$OverheadLight/Light.light_energy = 0
	$MainMenu.hide()
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://main.tscn")
