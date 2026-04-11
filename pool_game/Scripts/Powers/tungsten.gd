extends StaticBody3D

@export var power_type: String = "Modifier"
@export var power_scene_name = "tungsten"
@export var cost = 8

func get_target() -> String:
	var valid_balls = []
	var root = get_tree().get_root()
	_find_balls_in_tree(root, valid_balls)
	
	var shape = $Area3D.get_node("CollisionShape3D").shape
	var closest_ball = null
	var closest_distance = shape.size.length()
	
	for ball in valid_balls:
		var distance = global_position.distance_to(ball.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_ball = ball
	
	if closest_ball:
		return str(closest_ball.get_path())
	return ""
	
func apply_to(target: Node) -> void:
	if target is RigidBody3D:
		target.mass *= 11
		var mesh = target.get_node_or_null("MeshInstance3D")
		if mesh:
			var mat = mesh.get_active_material(0)
			if mat:
				mat = mat.duplicate()
				mat.albedo_color = Color.GRAY
				mat.metallic = 1.0
				mat.roughness = 0.1
				mesh.set_surface_override_material(0, mat)
	
func canPlace() -> bool:
	var valid_balls = []
	var root = get_tree().get_root()
	_find_balls_in_tree(root, valid_balls)
	
	var detected = []
	var shape = $Area3D.get_node("CollisionShape3D").shape
	
	for ball in valid_balls:
		var distance = global_position.distance_to(ball.global_position)
		# Check if ball is within the box bounds (approximate sphere-box collision)
		if distance < shape.size.length() * 0.5:
			detected.append(ball)
	
	if detected.size() != 1:
		return false
	
	return true

func _find_balls_in_tree(node: Node, result: Array) -> void:
	if node.is_in_group("balls"):
		result.append(node)
	
	for child in node.get_children():
		_find_balls_in_tree(child, result)
