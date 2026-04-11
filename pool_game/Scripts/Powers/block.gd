extends StaticBody3D

@export var power_type: String = "Object"
@export var power_scene_name = "block"
@export var cost = 15

func canPlace() -> bool:
	var bodies = $Area3D.get_overlapping_areas()
	if len(bodies) != 0:
		return false
	return true
