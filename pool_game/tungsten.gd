extends StaticBody3D

@onready var occupied = 0
@export var power_type: String = "Modifier"
@export var power_scene_name = "tungsten"

func _on_area_3d_area_entered(area: Area3D) -> void:
	print(occupied)
	occupied += 1

func _on_area_3d_area_exited(area: Area3D) -> void:
	print(occupied)
	occupied -=1
	
func power() -> bool:
	var bodies = $Area3D.get_overlapping_areas()
	print(bodies)
	if len(bodies) != 1:
		print("Too many or Too little modified")
		return false
	var object = bodies[0].get_parent()
	if object is RigidBody3D:
		object.mass = 11
		var mesh = object.get_node_or_null("MeshInstance3D")
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
