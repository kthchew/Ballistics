extends StaticBody3D

@onready var occupied = 0
@export var power_type: String = "Object"
@export var power_scene_name = "block"

func _on_area_3d_area_entered(area: Area3D) -> void:
	occupied += 1

func _on_area_3d_area_exited(area: Area3D) -> void:
	occupied -=1

func power() -> bool:
	return occupied == 0
