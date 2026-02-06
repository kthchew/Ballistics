extends Line2D


@onready var cue_ball = $"../../CueBall"
@onready var main = $"../../../Main"
var shoot_vec: Vector2 = Vector2(0, 0)

# in real life, 30 mph break == 13.4112 m/s
# max break velocity should be about 1350 m/s

func _input(event: InputEvent) -> void:
	if main != null and main.playing and event.is_action("click") and shoot_vec != null:
		print("hitting: ", shoot_vec)
		#playing = false
		var hit_vec = Vector3(shoot_vec.x, 0, shoot_vec.y)
		var hit_strength: float = 1.7e-4 * hit_vec.length() ** 2
		var hit_dir: Vector3 = hit_vec.normalized()
		print("Hit vector length: " + str(hit_strength))
		cue_ball.apply_central_impulse(hit_strength * hit_vec)


func draw_shoot_line():
	# Subtracting get_global_position() converts the mouse position to local
	var mouse_pos: Vector2 = get_parent().get_local_mouse_position()
	
	var camera: Camera3D = get_viewport().get_camera_3d()
	var ball_pos: Vector3 = cue_ball.global_position
	var ball_screen_pos: Vector2 = camera.unproject_position(ball_pos) - get_global_position()
	
	shoot_vec = ball_screen_pos - mouse_pos
	shoot_vec = min(200, 0.7 * shoot_vec.length()) * shoot_vec.normalized()
	
	# Draw one endpoint of line at the ball
	set_point_position(0, ball_screen_pos)
	
	# Draw other endpoint toward the mouse position
	set_point_position(1, ball_screen_pos - shoot_vec)


func _process(delta):
	if main == null:
		return
	if main.playing:
		draw_shoot_line()
	else:
		set_point_position(0, Vector2(-1, -1))
		set_point_position(1, Vector2(-1, -1))
	

func _on_main_new_turn() -> void:
	pass
	#playing = true
