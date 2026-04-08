extends StaticBody3D

@export var power_type: String = "Modifier"
@export var power_scene_name = "tungsten"

func get_target() -> Node:
	var bodies = $Area3D.get_overlapping_areas()
	if bodies.size() != 1:
		return null
	return bodies[0].get_parent()

func apply_to(target: Node) -> bool:
	if target is RigidBody3D:
		target.mass = 11
		var mesh = target.get_node_or_null("MeshInstance3D")
		if mesh:
			var mat = mesh.get_active_material(0)
			if mat:
				mat = mat.duplicate()
				mat.albedo_color = Color.GRAY
				mat.metallic = 1.0
				mat.roughness = 0.1
				mesh.set_surface_override_material(0, mat)
		return true
	return false

func canPlace() -> bool:
	var bodies = $Area3D.get_overlapping_areas()
	print(bodies)
	if len(bodies) != 1:
		return false
	var object = bodies[0].get_parent()
	if object is RigidBody3D:
		return true
	return false
