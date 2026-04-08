extends StaticBody3D

@onready var occupied = 0
@export var power_type: String = "Modifier"
@export var power_scene_name = "tnt"

func _on_area_3d_area_entered(area: Area3D) -> void:
	print(occupied)
	occupied += 1

func _on_area_3d_area_exited(area: Area3D) -> void:
	print(occupied)
	occupied -=1
	
func power() -> bool:
	var areas = $Area3D.get_overlapping_areas()
	print(areas)
	if len(areas) != 1:
		print("Too many or Too little modified")
		return false
	
	var obj = areas[0].get_parent()

	var name_lower = obj.name.to_lower()

	if not name_lower.contains("ball") and not name_lower.contains("table"):
		print("TNT deleting:", obj.name)
		obj.queue_free()
		get_node("/root/Main").objects -= 1
		return true

	print("TNT cannot delete:", obj.name)
	return false
	
func canPlace() -> bool:
	var areas = $Area3D.get_overlapping_areas()
	print(areas)
	if len(areas) != 1:
		return false
	
	var obj = areas[0].get_parent()

	var name_lower = obj.name.to_lower()

	if not name_lower.contains("ball") and not name_lower.contains("table"):
		return true

	return false
