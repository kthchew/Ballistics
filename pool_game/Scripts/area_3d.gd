extends Area3D

func _on_area_entered(area: Area3D) -> void:
	if not area.name.contains("Ball"):
		return
		
	var player = get_node("AudioStreamPlayer3D")
	player.play()
