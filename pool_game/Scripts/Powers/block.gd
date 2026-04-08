extends StaticBody3D

@export var power_type: String = "Object"
@export var power_scene_name = "block"

func canPlace() -> bool:
	return len($Area3D.get_overlapping_areas()) == 0
