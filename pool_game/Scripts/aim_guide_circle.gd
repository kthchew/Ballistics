extends Node2D

func _draw():
	var viewport_dimension: float
	var camera_dimension: float
	var camera := get_viewport().get_camera_3d()
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		viewport_dimension = get_viewport().size.x
	else:
		viewport_dimension = get_viewport().size.y
	if camera.projection == Camera3D.ProjectionType.PROJECTION_PERSPECTIVE:
		# no idea but this is the math copilot autofilled for me and it looks right so seems fine
		camera_dimension = 2.0 * tan(deg_to_rad(camera.fov) / 2.0) * abs(camera.global_position.y)
	else:
		camera_dimension = camera.size
	var ball_3d_rad: float = Constants.BALL_RADIUS
	var ball_2d_rad = (ball_3d_rad / camera_dimension) * viewport_dimension
	var width = 2
	var width_adjusted_rad = ball_2d_rad - width / 2.0
	draw_arc(Vector2(0, 0), width_adjusted_rad, 0, 2 * PI, 20, Color(1, 1, 1), width)
