extends Control

signal hole_selected(hole_ind: int)

const hole_btn_scene = preload("res://hole_button.tscn")
@onready var camera = $"../../CameraPivot/Camera3D"
@onready var holes = $"../../TableGroup/Table/Holes"

func _ready() -> void:
	place_hole_buttons()

func place_hole_buttons() -> void:
	for i in range(6):
		var hole_btn = hole_btn_scene.instantiate()
		add_child(hole_btn)
		var hole_marker = holes.get_children()[i].find_children("HoleMarker")[0]
		var screen_pos = camera.unproject_position(hole_marker.global_position)
		hole_btn.position = screen_pos - hole_btn.size / 2
		
		hole_btn.pressed.connect(func(): hole_selected.emit(i))
