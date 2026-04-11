extends StaticBody3D

@export var power_type: String = "Modifier"
@export var power_scene_name = "tnt"
@export var cost = 10

func get_target() -> String:
	var valid_targets = []
	var root = get_tree().get_root()
	_find_targets_in_tree(root, valid_targets)
	
	var shape = $Area3D.get_node("CollisionShape3D").shape
	var closest_target = null
	var closest_distance = shape.size.length()
	
	for target in valid_targets:
		var distance = global_position.distance_to(target.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_target = target
	
	if closest_target:
		return str(closest_target.get_path())
	return ""

func canPlace() -> bool:
	var valid_targets = []
	var root = get_tree().get_root()
	_find_targets_in_tree(root, valid_targets)
	
	var detected = []
	var shape = $Area3D.get_node("CollisionShape3D").shape
	
	for target in valid_targets:
		var distance = global_position.distance_to(target.global_position)
		# Check if target is within the box bounds (approximate sphere-box collision)
		if distance < shape.size.length() * 0.5:
			detected.append(target)
	
	if detected.size() != 1:
		return false
	
	return true

func _find_targets_in_tree(node: Node, result: Array) -> void:
	var name_lower = node.name.to_lower()
	if node.is_in_group("balls") or name_lower.contains("table"):
		result.append(node)
	
	for child in node.get_children():
		_find_targets_in_tree(child, result)
