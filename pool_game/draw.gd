extends Node2D

# We store the data of what needs to be drawn here
var _circles: Array[Dictionary] = []

# This is the simple function you will call from your other scripts!
func circle(pos: Vector2, radius: float, color: Color):
	_circles.append({"pos": pos, "radius": radius, "color": color})
	queue_redraw() # Tells Godot to update the canvas

# If you ever want to wipe the drawings off the screen
func clear_all():
	_circles.clear()
	queue_redraw()

# Godot's internal draw loop automatically handles the rest
func _draw():
	for c in _circles:
		draw_circle(c.pos, c.radius, c.color)
