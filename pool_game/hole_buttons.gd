extends Control

signal hole_selected(hole_ind: int)

const hole_btn_scene = preload("res://hole_button.tscn")
@onready var camera = $/root/Main/CameraPivot/Camera3D

func _ready() -> void:
	place_hole_buttons()

func place_hole_buttons() -> void:
	for i in range(6):
		var hole_btn = hole_btn_scene.instantiate()
		hole_btn.name = "HoleButton" + str(i + 1)
		add_child(hole_btn)
		var path_str = "/root/Main/TableGroup/Table/Holes/Hole" + str(i + 1) + "/HoleMarker"
		var hole_marker = get_node(path_str)
		var screen_pos = camera.unproject_position(hole_marker.global_position)
		hole_btn.position = screen_pos - hole_btn.size / 2
		
		hole_btn.pressed.connect(func(): hole_selected.emit(i))
