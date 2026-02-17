extends Area3D


func _on_body_entered(body: Node3D) -> void:
	if not body.name.contains("Ball"):
		return
	body.collision_mask = 1

func _on_body_exited(body: Node3D) -> void:
	if not body.name.contains("Ball"):
		return
	body.collision_mask = 1 | 2
