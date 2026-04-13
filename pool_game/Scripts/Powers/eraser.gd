extends StaticBody3D

@export var power_type: String = "Modifier"
@export var power_scene_name = "eraser"
@export var cost := 10

func _ready() -> void:
	add_to_group("modifiers")

func get_target() -> String:
	var balls = []
	var root = get_tree().get_root()
	_find_balls_in_tree(root, balls)
	
	var shape = $Area3D.get_node("CollisionShape3D").shape
	
	for ball in balls:
		var distance = global_position.distance_to(ball.global_position)
		if distance < shape.size.length() * 0.5:
			if is_hovered_object_modified(ball):
				return str(ball.get_path())
	
	return ""

func _find_balls_in_tree(node: Node, result: Array) -> void:
	if node.is_in_group("balls"):
		result.append(node)
	
	for child in node.get_children():
		_find_balls_in_tree(child, result)

func apply_to(target: Node) -> void:
	if not target:
		return

	if target is RigidBody3D:
		target.mass = 1.0
		
		var mesh = target.get_node_or_null("MeshInstance3D")
		if mesh:
			var mat = mesh.get_active_material(0)
			if mat:
				mat = mat.duplicate()
				mat.albedo_color = Color.WHITE
				mat.metallic = 0.0
				mat.roughness = 1.0
				mesh.set_surface_override_material(0, mat)

func canPlace() -> bool:
	var balls = []
	var root = get_tree().get_root()
	_find_balls_in_tree(root, balls)
	
	var shape = $Area3D.get_node("CollisionShape3D").shape
	var detected = []
	
	for ball in balls:
		var distance = global_position.distance_to(ball.global_position)
		if distance < shape.size.length() * 0.5:
			if is_hovered_object_modified(ball):
				detected.append(ball)
	
	return detected.size() == 1


func is_hovered_object_modified(hovered_object: Node) -> bool:
	if hovered_object is RigidBody3D:
		if hovered_object.mass != 1.0:
			return true

		var mesh = hovered_object.get_node_or_null("MeshInstance3D")
		if mesh:
			var mat = mesh.get_active_material(0)
			if mat and (mat.albedo_color == Color(1.0, 0.592, 0.929, 1.0) or mat.albedo_color ==Color(0.8, 0.8, 0.8, 1.0)):
				return true

	return false
