extends StaticBody3D

@onready var occupied = 0
@export var power_type: String = "Modifier"

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
	print(object.Mass)
	object.mareasass = 11
	var mat = object.get_node("MeshInstance3D").get_active_material(0).duplicate()
	mat.albedo_color = Color.GRAY
	mat.metallic = 1.0
	mat.roughness = 0.1
	object.get_node("MeshInstance3D").set_surface_override_material(0, mat)
	print(object.Mass)
	return true
