extends Node2D

func _draw():
	var viewport_height = get_viewport().size.y
	var camera_height = $"../../../../CameraPivot/Camera3D".size
	var ball_3d_rad: float = Constants.BALL_RADIUS
	var ball_2d_rad = (ball_3d_rad / camera_height) * viewport_height
	var width = 2
	var width_adjusted_rad = ball_2d_rad - width / 2.0
	draw_arc(Vector2(0, 0), width_adjusted_rad, 0, 2 * PI, 20, Color(1, 1, 1), width)
