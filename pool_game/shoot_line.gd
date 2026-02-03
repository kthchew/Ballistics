extends Line2D


@onready var cue_ball = $"../../CueBall"
var dir: Vector2 = Vector2(0, 0)
var playing: bool = true

func _input(event: InputEvent) -> void:
	if playing and event.is_action("click") and dir != null:
		print("hitting: ", dir)
		playing = false
		cue_ball.apply_central_impulse(5 * Vector3(dir.x, 0, dir.y))


func draw_shoot_line():
	# Draw one endpoint at the mouse position
	# Subtracting get_global_position() converts the mouse position to local
	var mouse_pos = get_parent().get_local_mouse_position()
	set_point_position(0, mouse_pos)
	
	# Draw other endpoint at the cue ball position
	var camera = get_viewport().get_camera_3d()
	var ball_pos = cue_ball.global_position
	var ball_screen_pos = camera.unproject_position(ball_pos) - get_global_position()
	set_point_position(1, ball_screen_pos)
	
	dir = ball_screen_pos - mouse_pos


func _process(delta):
	if playing:
		draw_shoot_line()
	else:
		set_point_position(0, Vector2(-1, -1))
		set_point_position(1, Vector2(-1, -1))		
	

func _on_main_new_turn() -> void:
	playing = true
