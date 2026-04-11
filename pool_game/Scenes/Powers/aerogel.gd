extends StaticBody3D

@export var power_type: String = "Modifier"
@export var power_scene_name = "aerogel"
@export var cost = 8
	
func get_target() -> String:
	var areas = $Area3D.get_overlapping_areas()
	if areas.size() != 1:
		return ""
	
	var target = areas[0].get_parent()
	return str(target.get_path())

func apply_to(target: Node) -> void:
	if target is RigidBody3D:
		target.mass *= 0.009
		var mesh = target.get_node_or_null("MeshInstance3D")
		if mesh:
			var mat = mesh.get_active_material(0)
			if mat:
				mat = mat.duplicate()
				mat.albedo_color = Color.PINK
				mat.metallic = 0.0
				mat.roughness = 0.1
				mesh.set_surface_override_material(0, mat)
	
func canPlace() -> bool:
	var bodies = $Area3D.get_overlapping_areas()
	if len(bodies) != 1:
		return false
	var object = bodies[0].get_parent()
	if object is RigidBody3D:
		return true
	return false
