extends StaticBody3D

@export var power_type := "Modifier"
@export var power_scene_name := "tnt"

func get_target() -> Node:
	var areas = $Area3D.get_overlapping_areas()
	if areas.size() != 1:
		return null
	return areas[0].get_parent()

func apply_to(target: Node) -> bool:
	if target == null:
		return false

	var name_lower = target.name.to_lower()

	if not name_lower.contains("ball") and not name_lower.contains("table"):
		print("TNT deleting:", target.name)
		target.queue_free()

		var main = get_node_or_null("/root/Main")
		if main and main.has_variable("objects"):
			main.objects = max(0, main.objects - 1)

		return true

	print("TNT cannot delete:", target.name)
	return false
