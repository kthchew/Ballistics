extends Area3D

var wall_collision_mask := 1
var table_collision_mask := 2

func _on_body_entered(body: Node3D) -> void:
	if not body.name.contains("Ball"):
		return
	# on ball entering hole, collide with only walls, not table
	body.collision_mask = 1

func _on_body_exited(body: Node3D) -> void:
	if not body.name.contains("Ball"):
		return
	# on ball exiting hole, collide with walls and table
	body.collision_mask = 1 | 2
