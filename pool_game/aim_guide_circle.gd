extends Node2D

func _draw():
	var viewport_height = 1080
	var camera_height = 150
	var ball_3d_rad = 2.85
	var ball_2d_rad = (ball_3d_rad / camera_height) * viewport_height
	# Finally, draw the arc.
	var width = 2
	var width_adjusted_rad = ball_2d_rad - width / 2
	draw_arc(Vector2(0, 0), width_adjusted_rad, 0, 2 * PI, 20, Color(1, 1, 1), width)
