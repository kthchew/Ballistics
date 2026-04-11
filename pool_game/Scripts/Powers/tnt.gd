extends StaticBody3D

@export var power_type: String = "Modifier"
@export var power_scene_name = "tnt"
@export var cost = 10

func get_target() -> String:
	var areas = $Area3D.get_overlapping_areas()
	if areas.size() != 1:
		return ""
	
	var target = areas[0].get_parent()
	return str(target.get_path())

func apply_to(target: Node) -> void:
	var low = target.name.to_lower()
	if not low.contains("ball") and not low.contains("table"):
		target.queue_free()
		get_node("/root/Main").objects -= 1
	
func canPlace() -> bool:
	var areas = $Area3D.get_overlapping_areas()
	if len(areas) != 1:
		return false
	
	var obj = areas[0].get_parent()

	var name_lower = obj.name.to_lower()

	if not name_lower.contains("ball") and not name_lower.contains("table"):
		return true

	return false
