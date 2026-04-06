extends Area3D

var wall_mask := 1
var table_mask := 2

func _on_body_entered(body: Node3D) -> void:
	if not body.name.contains("Ball"):
		return
	# on ball entering hole, collide with only walls and balls, not table
	body.collision_mask = wall_mask

func _on_body_exited(body: Node3D) -> void:
	if not body.name.contains("Ball"):
		return
	# on ball exiting hole, collide with walls, balls, and table
	body.collision_mask = wall_mask | table_mask
