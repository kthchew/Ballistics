extends Node3D


@onready var debug_label: Label = $UI/DebugLabel
@onready var info_label: Label = $UI/InfoLabel
@onready var slider = $UI/ForceSlider
@onready var fire_button = $UI/FireButton
@onready var aimer = $UI/Aimer
@onready var camera = $CameraPivot/Camera3D
@onready var hole_buttons = $UI/HoleButtons
@onready var aim_visuals = $UI/AimVisuals
@onready var cue_stick = $UI/AimVisuals/CueStick
@onready var shape_cast = $ShapeCast3D

enum GameState {AIMING, MIDTURN, PLACING, PICKPOCKET, ENDED}
const STATIC_TICKS_THRESHOLD: int = 60
const SPEED_THRESH: float = 0.25
const ANGULAR_SPEED_THRESH: float = 0.25
# sometimes we change the below constant for playtesting
const BALLS_BEFORE_EIGHT: int = 7

var has_aimed := false
var cue_ball: RigidBody3D = null
var balls: Array[RigidBody3D] = []
# physics defaults to 60 ticks per second
var cur_static_ticks = 0
var player_ind: int = 0
var scores: Array[int] = [0, 0]
var balls_sunk: Array[int] = [0, 0]
var game_state: GameState = GameState.AIMING
var turn_num: int = 0
var solids_player = -1
var next_solids_player = -1
var winner: int = -1
var play_again: bool = false
var target_hole: int = -1

const ball_scene = preload("res://ball.tscn")
const ball_script = preload("res://ball.gd")
const ball_shape = preload("res://ball_shape.tres")

func _ready() -> void:
	
	create_balls()
	start_game()
	
	aim_visuals.visible = false
	$OverheadLight/Light.light_energy = 1000
	
	$UI/AimInputRegion.aim_changed.connect(_on_aim_changed)
	slider.value_changed.connect(_on_force_changed)
	fire_button.pressed.connect(_on_fire_pressed)
	hole_buttons.hole_selected.connect(_on_hole_selected)
	
func _on_aim_changed(touch_pos: Vector2):
	if game_state == GameState.MIDTURN or game_state == GameState.ENDED:
		return
		
	if game_state == GameState.PLACING:
		var ray_origin = camera.project_ray_origin(touch_pos)
		var ray_normal = camera.project_ray_normal(touch_pos)
		var drop_plane = Plane(Vector3.UP, Vector3(0, ball_script.BALL_RADIUS, 0))
		var intersection = drop_plane.intersects_ray(ray_origin, ray_normal)
		cue_ball.reset(intersection)
		start_round()
		return
		
	if not has_aimed:
		has_aimed = true

	var ball_screen_pos = camera.unproject_position(cue_ball.global_position)
	var dir = ball_screen_pos - touch_pos
	#dir = Vector2(30, 30)

	if dir.length() < 20:
		return

	var angle = dir.angle()
	var dir_norm = dir.normalized()
	
	cast_aim_ray(dir_norm)

	var ball_center_3d = cue_ball.global_position
	var ball_edge_3d = ball_center_3d + Vector3(5, 0, 0)
	var center_screen = camera.unproject_position(ball_center_3d)
	var edge_screen = camera.unproject_position(ball_edge_3d)
	var ball_radius_px = (edge_screen - center_screen).length()
	var cue_pos = ball_screen_pos - dir_norm * ball_radius_px
	
	cue_stick.update_position(cue_ball.global_position)
	cue_stick.set_angle(angle)
	aim_visuals.visible = true

func _on_force_changed(value):
	var normalized = value / $UI/ForceSlider.max_value
	cue_stick.set_force_strength(normalized)
	
func _on_fire_pressed():
	var strength = slider.value
	var angle = cue_stick.angle

	var dir = Vector3(cos(angle), 0, sin(angle)).normalized()
	var force = dir * (strength * 5)

	var up = Vector3.UP
	if abs(dir.dot(up)) > 0.9:
		up = Vector3.FORWARD

	var right = dir.cross(up).normalized()
	var forward = right.cross(dir).normalized()

	var face_radius = 0.5
	var joy = aimer.output
	var offset_3d = right * (joy.x * face_radius) + forward * (-joy.y * face_radius)

	cue_stick.striking = true

	cue_ball.first_hit_ball_num = 0
	game_state = GameState.MIDTURN
	
	var tween := create_tween()

	var target_pos = cue_ball.global_position - cue_stick.aim_direction * ball_script.BALL_RADIUS

	var distance = cue_stick.global_position.distance_to(target_pos)

	var base_speed = 20.0
	var scaled = pow(strength, 0.6)
	var speed = base_speed * (0.4 + 0.6 * scaled)

	var duration = distance / speed

	tween.tween_property(cue_stick, "global_position", target_pos, duration)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_IN_OUT)

	tween.tween_callback(func():
		#aim_visuals.visible = false
		cue_stick.striking = false
		cue_ball.apply_impulse(force, offset_3d)
	)
	print("STRENGTH:", strength)
	if strength > 95.0:
		shake_camera(.5, .1)
		sway_light(7, 7)
	has_aimed = false
	slider.value = 0
	cue_stick.set_force_strength(0.0)
	aimer._reset_knob()
	
func _on_hole_selected(hole_ind: int) -> void:
	target_hole = hole_ind
	hole_buttons.hide()
	start_round()
	
func _on_reset_button_pressed() -> void:
	start_game()
	
func cast_aim_ray(aim_dir: Vector2) -> void:
	var origin = cue_ball.global_position
	var dir = Vector3(aim_dir.x, 0, aim_dir.y)
	
	shape_cast.global_position = origin
	shape_cast.target_position = dir * 500
	shape_cast.collision_mask = 1 << 2
	print("cue ball collision layer ", cue_ball.collision_layer)
	print("origin = ", origin)
	print("dir = ", dir)
	print("target pos = ", shape_cast.target_position)
	#shape_cast.margin = 0
	
	shape_cast.force_shapecast_update()
	
	if shape_cast.is_colliding():
		var collision_point = shape_cast.get_collision_point(0)
		print("collision point = ", collision_point)
		var collision_normal = shape_cast.get_collision_normal(0)
		print("collision normal = ", collision_normal)
		var aim_guide_line = $UI/AimVisuals/AimGuideLine
		var ghost_ball_pos = collision_point + collision_normal * ball_script.BALL_RADIUS
		var collider = shape_cast.get_collider(0)
		print("collider = ", collider)
		aim_guide_line.set_point_position(0, camera.unproject_position(origin))
		aim_guide_line.set_point_position(1, camera.unproject_position(ghost_ball_pos))
		if shape_cast.get_collider(0).name.contains("Ball"):
			aim_guide_line.set_point_position(2, camera.unproject_position(ghost_ball_pos - 30 * collision_normal))
		else:
			aim_guide_line.set_point_position(2, camera.unproject_position(ghost_ball_pos))
	#if !hit_info.is_empty():
		#var collision_pos = hit_info["point"]
		#var collision_2d_pos = camera.unproject_position(collision_pos)
		#$UI/AimVisuals/AimGuideMarker.position = collision_2d_pos
	#print(collision_2d_pos)
	#
	#var collider = result["collider"]
	#if collider.name.contains("Ball"):
		#var bounce_dir = collider.global_position - collision_pos
		#var bounce_dir_2d = Vector2(bounce_dir.x, bounce_dir.z)
		#aim_guide_line.set_point_position(2, collision_2d_pos + 30 * bounce_dir_2d)
	
	
func create_balls() -> void:
	balls = []
	ball_scene.instantiate()
	for i in range(16):
		var ball: RigidBody3D = ball_scene.instantiate()
		add_child(ball)
		ball.ball_num = i
		ball.name = "Ball%s" % i
		balls.append(ball)
		color_ball(ball)
		if i == 0:
			cue_ball = ball
			cue_ball.body_entered.connect(cue_ball._on_body_entered)
			cue_ball.contact_monitor = true
			cue_ball.max_contacts_reported = 3
		else:
			ball.collision_layer += 1 << 2
	
func color_ball(ball_node: RigidBody3D) -> void:
	var texture_path = "res://ball_textures/Ball" + str(ball_node.ball_num) + ".jpg"
	var ball_texture = load(texture_path)
	
	var material: Material = StandardMaterial3D.new()
	material.albedo_texture = ball_texture
	material.roughness = 0.3
	
	var mesh = ball_node.get_node("MeshInstance3D")
	mesh.set_surface_override_material(0, material)
	
func pot_all_solids():
	for ball in balls:
		if ball.is_solid():
			process_fallen_ball(ball)
	
func start_game() -> void:
	
	cue_ball.reset(Vector3(-56, ball_script.BALL_RADIUS, 0))
	
	has_aimed = false
	game_state = GameState.AIMING
	
	player_ind = 0
	cur_static_ticks = 0
	solids_player = -1
	next_solids_player = -1
	scores = [0, 0]
	balls_sunk = [0, 0]
	turn_num = 0
	play_again = false
	target_hole = -1
	
	hole_buttons.hide()
	
	place_rack(56, 0)

func place_rack(x_shift: float, z_shift: float, spacing: float = 1.05):
	balls.sort_custom(func(a, b): return a.ball_num < b.ball_num)
	var ball_perm = range(16)
	ball_perm.erase(0)
	ball_perm.erase(8)
	ball_perm.shuffle()
	ball_perm.insert(0, 0)
	ball_perm.insert(5, 8)
	
	var new_balls: Array[RigidBody3D] = []
	for i in range(16):
		new_balls.append(balls[ball_perm[i]])
	balls = new_balls
	
	var ball_ind: int = 1
	for i in range(5):
		for j in range(i + 1):
			var x: float = x_shift + spacing * i * ball_script.BALL_RADIUS * sqrt(3)
			var z: float = z_shift + (-i + 2 * j) * ball_script.BALL_RADIUS * spacing
			balls[ball_ind].reset(Vector3(x, ball_script.BALL_RADIUS, z))
			balls[ball_ind].rotation = Vector3(PI/2, 0, PI)
			
			ball_ind += 1
	
func shake_camera(intensity: float, duration: float) -> void:
	print("Shake Camera")
	var cam := $CameraPivot/Camera3D
	var original :Vector3 = cam.rotation_degrees

	var tween := create_tween()
	
	# apply a shake with intensity (use a small decay factor to make it dampen)
	tween.tween_property(cam, "rotation_degrees", original + Vector3(intensity, intensity, intensity), duration / 2)
	
	# return to the original position, damping the effect over time
	tween.set_trans(Tween.TRANS_SINE)  # Set transition type to sine for smoothness
	tween.set_ease(Tween.EASE_OUT)     # Set easing type to ease out for dampening
	tween.tween_property(cam, "rotation_degrees", original, duration / 2)
	
func sway_light(amount: float, duration: float) -> void:
	var light := $OverheadLight/Light
	var tween := create_tween()
	var original_rot : Vector3 = light.rotation

	# Number of oscillations
	var cycles := 6
	var cycle_time := duration / cycles

	for i in range(cycles):
		# Exponentially decreasing amplitude
		var amp := deg_to_rad(amount * pow(0.55, i))

		# Target rotation for this half‑cycle (left or right)
		var target_rot : Vector3 = original_rot + Vector3(0, amp, 0)

		# Sway to one side
		tween.tween_property(light, "rotation", target_rot, cycle_time * 0.5)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

		# sway back past center to the opposite side
		var opposite_rot : Vector3 = original_rot - Vector3(0, amp, 0)
		tween.tween_property(light, "rotation", opposite_rot, cycle_time * 0.5)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# return to original rotation
	tween.tween_property(light, "rotation", original_rot, cycle_time * 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
func check_all_not_moving() -> bool:
	for ball in balls:
		if ball.get_linear_velocity().length() > SPEED_THRESH \
		or ball.get_angular_velocity().length() > ANGULAR_SPEED_THRESH:
			return false
	return true
	
func process_fallen_balls() -> void:
	var fallen_balls: Array[RigidBody3D] = find_fallen_balls()
	for ball in fallen_balls:
		process_fallen_ball(ball)

func find_fallen_balls() -> Array[RigidBody3D]:
	var fallen_balls: Array[RigidBody3D] = []
	for ball in balls:
		if ball.position.y < -10:
			print(ball.name + " fell")
			fallen_balls.append(ball)
	return fallen_balls
	
func end_game(winner: int) -> void:
	self.winner = winner
	game_state = GameState.ENDED
	for ball in balls:
		ball.freeze = true
		
func calc_hole_ind_from_pos(pos: Vector3) -> int:
	var hole_ind = 0
	
	if pos.z > 0:
		hole_ind += 3
	
	if pos.x > 50.91:
		hole_ind += 2
	elif pos.x > -50.91:
		hole_ind += 1
	
	return hole_ind
		
	
func process_fallen_ball(ball: RigidBody3D) -> void:
	if ball.is_eight_ball():
		var hole_ind = calc_hole_ind_from_pos(ball.position)
		if scores[player_ind] >= BALLS_BEFORE_EIGHT and target_hole == hole_ind:
			end_game(player_ind)
		else:
			end_game(1 - player_ind)
	
	elif not ball.is_cue_ball():
		if solids_player == -1:
			play_again = true
		if ball.is_solid():
			balls_sunk[0] += 1
			if solids_player == player_ind:
				play_again = true
		elif ball.is_stripe():
			balls_sunk[1] += 1
			if solids_player == 1 - player_ind:
				play_again = true
		
		if turn_num > 0 and solids_player == -1:
			if ball.is_solid():
				next_solids_player = player_ind
			elif ball.is_stripe():
				next_solids_player = 1 - player_ind
		
		if next_solids_player != -1:
			scores[next_solids_player] = balls_sunk[0]
			scores[1 - next_solids_player] = balls_sunk[1]
	
	ball.pot()
	
func check_for_first_hit_scratch() -> bool:
	var first_hit_ball_num = cue_ball.first_hit_ball_num
	if first_hit_ball_num == -1:
		return false
	if scores[player_ind] >= BALLS_BEFORE_EIGHT and first_hit_ball_num == 8:
		return false
	if solids_player == player_ind and not (1 <= first_hit_ball_num and first_hit_ball_num <= 7):
		return true
	if solids_player == 1 - player_ind and not (9 <= first_hit_ball_num and first_hit_ball_num <= 15):
		return true
	return false
	
func check_for_scratch():
	return cue_ball.potted or check_for_first_hit_scratch()

func end_round() -> void:
	
	cue_ball.first_hit_ball_num = -1
	target_hole = -1
	if next_solids_player != -1:
		solids_player = next_solids_player
	
	var scratched = check_for_scratch()
	
	if not scratched and play_again:
		play_again = false
		start_round()
		return
	
	play_again = false
	turn_num += 1
	player_ind = 1 - player_ind
	start_round(scratched)
		
func start_round(scratched_prev: bool = false) -> void:
	if scratched_prev:
		if balls[5].potted:
			end_game(player_ind)
		print("Scratch registered")
		game_state = GameState.PLACING
		cue_ball.pot()
		return
	
	if target_hole == -1 and scores[player_ind] >= BALLS_BEFORE_EIGHT:
		game_state = GameState.PICKPOCKET
		hole_buttons.show()
		return
	
	game_state = GameState.AIMING
	
func process_midturn():
	if game_state != GameState.MIDTURN:
		return
	#elif game_state == GameState.MIDTURN:
		#aim_visuals.visible = false
		
	process_fallen_balls()
	process_movement()

func process_movement():
	if check_all_not_moving():
		cur_static_ticks += 1
	else:
		cur_static_ticks = 0
		
	if cur_static_ticks == STATIC_TICKS_THRESHOLD:
		end_round()

func _physics_process(delta: float) -> void:
	process_midturn()
		
func _process(delta: float) -> void:
	fill_debug_label()
	fill_info_label()
	
func fill_debug_label() -> void:
	var label_txt = "Static Ticks: " + str(cur_static_ticks)
	label_txt += "\nGame State: " + str(game_state)
	label_txt += "\nCurrent Player Ind: " + str(player_ind)
	label_txt += "\nTurn Num: " + str(turn_num)
	label_txt += "\nPlayer 0 Score: " + str(scores[0])
	label_txt += "\nPlayer 1 Score: " + str(scores[1])
	label_txt += "\nSolids Sunk: " + str(balls_sunk[0])
	label_txt += "\nStripes Sunk: " + str(balls_sunk[1])
	label_txt += "\nSolids Player: " + str(solids_player)
	label_txt += "\nNext Solids Player: " + str(next_solids_player)
	label_txt += "\nFirst Hit: " + str(cue_ball.first_hit_ball_num)
	label_txt += "\nPlay Again: " + str(play_again)
	debug_label.text = label_txt

func fill_info_label() -> void:
	info_label.text = ""
	
	if game_state == GameState.ENDED:
		info_label.text = "Player " + str(winner + 1) + " won the game! Click the 'Reset Game' button to play again"
	
	if game_state != GameState.MIDTURN and game_state != GameState.ENDED:
		info_label.text += "Player " + str(player_ind + 1) + "'s turn.\n"
		if scores[player_ind] < BALLS_BEFORE_EIGHT:
			if player_ind == solids_player:
				info_label.text += "You are solids\n"
			elif 1 - player_ind == solids_player:
				info_label.text += "You are stripes\n"
	
	if game_state == GameState.PICKPOCKET:
		info_label.text += "Pick your target pocket for the 8-ball\n"
			
	if game_state == GameState.PLACING:
		info_label.text += "Your opponent scratched, click to place the cue ball\n"
