extends Control

signal hole_selected(hole_ind: int)

const hole_btn_scene = preload("res://Scenes/hole_button.tscn")
@onready var camera = $"../../CameraPivot/Camera3D"

func _ready() -> void:
	place_hole_buttons()
	
func style_hole_button(button):
	var state_to_color_map = {
		"normal": Color(0.225, 0.225, 0.225, 0.6), 
		"hover": Color(0.0, 0.0, 0.0, 0.6), 
		"pressed": Color(0.1, 0.1, 0.1, 0.3),
		"disabled":Color(0.1, 0.1, 0.1, 0.6)
	}
	for state in state_to_color_map:
		var style = button.get_theme_stylebox(state).duplicate()
		style.bg_color = state_to_color_map[state]
		if style is StyleBoxFlat:
			style.corner_radius_top_left = 50
			style.corner_radius_top_right = 50
			style.corner_radius_bottom_left = 50
			style.corner_radius_bottom_right = 50
			
			button.add_theme_stylebox_override(state, style)

func place_hole_buttons() -> void:
	for i in range(6):
		var hole_btn = hole_btn_scene.instantiate()
		hole_btn.name = "HoleButton" + str(i + 1)
		style_hole_button(hole_btn)
		add_child(hole_btn)
		
		hole_btn.pressed.connect(func(): hole_selected.emit(i))
	
	reposition_hole_buttons()
		
func reposition_hole_buttons() -> void:
	for i in range(6):
		var path_str = "../../TableGroup/Table/Holes/Hole" + str(i + 1) + "/HoleMarker"
		var hole_marker = get_node(path_str)
		var screen_pos = camera.unproject_position(hole_marker.global_position)
		var hole_btn = get_child(i)
		hole_btn.position = screen_pos - hole_btn.size / 2
