class_name CircleArtist extends Node2D

# We store the data of what needs to be drawn here
var _circles: Array[Dictionary] = []

# This is the simple function you will call from your other scripts!
func circle(pos: Vector3, radius: float, color: Color):
	if Constants.AI_DRAW_AIM_GUIDE:
		_rpc_add_circle.rpc(pos, radius, color)
	
@rpc("any_peer", "call_local")
func _rpc_add_circle(pos: Vector3, radius: float, color: Color):
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen_pos: Vector2 = camera.unproject_position(pos)
	_circles.append({"pos": screen_pos, "radius": radius, "color": color})
	queue_redraw() # Tells Godot to update the canvas

# If you ever want to wipe the drawings off the screen
func clear_all():
	if Constants.AI_DRAW_AIM_GUIDE:
		_rpc_clear_all.rpc()
	
@rpc("any_peer", "call_local")
func _rpc_clear_all():
	_circles.clear()
	queue_redraw()

# Godot's internal draw loop automatically handles the rest
func _draw():
	for c in _circles:
		draw_circle(c.pos, c.radius, c.color)
