extends Node2D

func _draw():
	var radius : float = 20
	# Finally, draw the arc.
	draw_arc(Vector2(0, 0), radius, 0, 2 * PI, 20, Color(1, 1, 1), 2)
