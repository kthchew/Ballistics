extends Node3D


@onready var debug_label: Label = $Control/DebugLabel
@onready var cue_ball: RigidBody3D = $CueBall
@onready var slider = $UI/ForceSlider
@onready var fire_button = $UI/FireButton
@onready var aimer = $UI/Aimer
@onready var ai_controller = $AIController3D
@onready var camera = $CameraPivot/Camera3D
@onready var cue_stick = $CueStick

enum GameState {AIMING, MIDTURN, PLACING}

var has_aimed := false
var balls: Array[RigidBody3D] = []
var speed_threshold: float = 0.25
var angular_speed_threshold: float = 0.25
# physics defaults to 60 ticks per second
var static_ticks_threshold = 5
var cur_static_ticks = 0
var player_ind: int = 0
var scores: Array[int] = [0, 0]
var balls_sunk: Array[int] = [0, 0]
@export var game_state: GameState = GameState.AIMING
var turn_num: int = 0
var cue_ball_potted: bool = false
var solids_player = -1

const ball_scene = preload("res://ball.tscn")

var _ai_ewma_wins = 0.0
var _ai_games_played_current_stage = 0
var _ai_current_stage = 0

func _ready() -> void:
	cue_stick.visible = false
	$UI/AimInputRegion.aim_changed.connect(_on_aim_changed)
	slider.value_changed.connect(_on_force_changed)
	fire_button.pressed.connect(_on_fire_pressed)
	$OverheadLight/Light.light_energy = 1000
	
	ai_controller.init(self)
	ai_controller.fire.connect(_on_fire_pressed)
	
	start_game()

func start_game() -> void:
	cur_static_ticks = 0
	while balls.size() > 1:
		balls[1].queue_free()
		remove_child(balls[1])
		balls.remove_at(1)
	scores = [0, 0]
	balls_sunk = [0, 0]
	balls = []
	balls.append(cue_ball)
	init_break_triangle(56, 0)
	#if ai_controller.heuristic == 'model' and _ai_current_stage < 8:
		#var required_win_rate = 0.7 if _ai_current_stage > 0 else 0.9
		#shuffle_random_balls(_ai_current_stage, max(1, _ai_current_stage))
		#if _ai_ewma_wins > required_win_rate and _ai_games_played_current_stage > 100:
			#_ai_current_stage += 1
			#_ai_ewma_wins = 0
			#_ai_games_played_current_stage = 0
			#ai_controller.reset_after = max(5, _ai_current_stage * 10)
			
	shuffle_random_balls(0, 0)
		
	cue_stick.visible = false
	cue_ball_potted = false
	game_state = GameState.AIMING
	cue_ball.first_hit_ball_num = -1

func _on_aim_changed(touch_pos: Vector2):
	if game_state == GameState.MIDTURN:
		return
		
	if game_state == GameState.PLACING:
		print("Shooting placing ray")
		var ray_origin = camera.project_ray_origin(touch_pos)
		var ray_normal = camera.project_ray_normal(touch_pos)
		
		var drop_plane = Plane(Vector3.UP, Vector3(0, 2.85, 0))
		
		# 3. Get intersection point
		var intersection = drop_plane.intersects_ray(ray_origin, ray_normal)
		reset_cue_ball(intersection)
		return
		
	if not has_aimed:
		has_aimed = true

	var ball_screen_pos = camera.unproject_position(cue_ball.global_position)
	var dir = ball_screen_pos - touch_pos

	if dir.length() < 20:
		return

	var angle = dir.angle()
	var dir_norm = dir.normalized()

	var ball_center_3d = cue_ball.global_position
	var ball_edge_3d = ball_center_3d + Vector3(5, 0, 0)
	var center_screen = $CameraPivot/Camera3D.unproject_position(ball_center_3d)
	var edge_screen = $CameraPivot/Camera3D.unproject_position(ball_edge_3d)
	var ball_radius_px = (edge_screen - center_screen).length()
	var cue_pos = ball_screen_pos - dir_norm * ball_radius_px
	
	cue_stick.update_position(cue_ball.global_position)
	cue_stick.set_angle(angle)
	cue_stick.visible = true

func _on_force_changed(value):
	var normalized = value / $UI/ForceSlider.max_value
	cue_stick.set_force_strength(normalized)
	
func shake_camera(intensity: float, duration: float) -> void:
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
	
func _on_fire_pressed():
	var sync = get_tree().get_nodes_in_group("SYNC")
	sync[0]._demo_record_process()
	
	ai_controller.reward -= 0.05
	var strength: float
	var angle: float
	var joy: Vector2
	if ai_controller.heuristic == 'human':
		strength = slider.value
		angle = cue_stick.angle
		joy = aimer.output
	else:
		strength = (ai_controller.action_power ** 2) * 100
		#ai_controller.reward += ai_controller.action_power / 10 / 2
		angle = ai_controller.action_angle
		joy = Vector2(ai_controller.action_posx, ai_controller.action_posy)

	var dir = Vector3(cos(angle), 0, sin(angle)).normalized()
	var force = dir * (strength * 3)

	var up = Vector3.UP
	if abs(dir.dot(up)) > 0.9:
		up = Vector3.FORWARD

	var right = dir.cross(up).normalized()
	var forward = right.cross(dir).normalized()

	var face_radius = 0.5
	
	var offset_3d = right * (joy.x * face_radius) + forward * (-joy.y * face_radius)

	cue_stick.striking = true

	var tween := create_tween()

	var R = 2.85
	var target_pos = cue_ball.global_position - cue_stick.aim_direction * R

	var distance = cue_stick.global_position.distance_to(target_pos)

	var base_speed = 20.0
	var scaled = pow(strength, 0.6)
	var speed = base_speed * (0.4 + 0.6 * scaled)

	var duration = distance / speed

	tween.tween_property(cue_stick, "global_position", target_pos, duration)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_IN_OUT)

	tween.tween_callback(func():
		cue_stick.visible = false
		cue_stick.striking = false
		cue_ball.apply_impulse(force, offset_3d)
	)
	#print("STRENGTH:", strength)
	if strength > 95.0:
		shake_camera(.5, .1)
		sway_light(7, 7)
	has_aimed = false
	slider.value = 0
	cue_stick.set_force_strength(0.0)
	aimer._reset_knob()

func color_ball(ball_node: RigidBody3D, ball_num, colors) -> void:
	var mesh = ball_node.get_node("MeshInstance3D")
	var material: Material = StandardMaterial3D.new()
	
	ball_node.rotation = Vector3(0, 0, PI / 2)
	
	if ball_num > 8:
		var gradient: Gradient = Gradient.new()
		gradient.add_point(0.4, Color(1, 1, 1))
		gradient.add_point(0.4, Color(0, 0, 0))
		gradient.add_point(0.6, Color(0, 0, 0))
		gradient.add_point(0.6, Color(1, 1, 1))
		gradient.remove_point(0)
		gradient.remove_point(0)
		var gradient_texture: GradientTexture2D = GradientTexture2D.new()
		gradient_texture.fill_from = Vector2(0.5, 0)
		gradient_texture.fill_to = Vector2(0.5, 1)
		gradient_texture.gradient = gradient
		material.albedo_texture = gradient_texture
	
	var color_num = ball_num
	if color_num > 8:
		color_num -= 8
	var color = colors[color_num - 1]
	material.albedo_color = Color(color[0] / 255.0, color[1] / 255.0, color[2] / 255.0)
	
	mesh.set_surface_override_material(0, material)
	
func add_to_ewma(won: bool):
	var value = 1.0 if won else 0.0
	var alpha = 0.04
	_ai_ewma_wins = alpha * value + (1 - alpha) * _ai_ewma_wins
	_ai_games_played_current_stage += 1

func shuffle_random_balls(solid_count: int, stripe_count: int) -> void:
	var sorted_balls = balls
	sorted_balls.sort_custom(func(a,b): return a.ball_num < b.ball_num)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	
	var total_solids := 7
	var total_stripes := 7
	var ball_radius := 2.85
	var min_spacing := 6.0
	
	# compute sunk counts and set state
	balls_sunk[0] = total_solids - int(clamp(solid_count, 0, total_solids))
	balls_sunk[1] = total_stripes - int(clamp(stripe_count, 0, total_stripes))
	
	# pick which solid and stripe indices remain on table
	var solid_indices := []
	for i in range(1, 1 + total_solids):
		solid_indices.append(i) # balls[1..7]
	
	var stripe_indices := []
	for i in range(9, 9 + total_stripes):
		stripe_indices.append(i) # balls[9..15]
	
	solid_indices.shuffle()
	stripe_indices.shuffle()
	
	var solids_remaining := solid_indices.slice(0, clamp(solid_count, 0, total_solids))
	var stripes_remaining := stripe_indices.slice(0, clamp(stripe_count, 0, total_stripes))
	
	var _in_list: Callable = func (val, arr):
		for e in arr:
			if e == val:
				return true
		return false
	
	# mark balls as hidden or visible based on selection
	for i in range(sorted_balls.size()):
		var ball = sorted_balls[i]
		if ball == null:
			continue
	
		# solids 1..7
		if i >= 1 and i <= 7:
			if not _in_list.call(i, solids_remaining):
				# sink this ball
				ball.hide()
				ball.collision_layer = 0
				ball.collision_mask = 0
				ball.set_freeze_enabled(true)
	
		# stripes 9..15
		elif i >= 9 and i <= 15:
			if not _in_list.call(i, stripes_remaining):
				ball.hide()
				ball.collision_layer = 0
				ball.collision_mask = 0
				ball.set_freeze_enabled(true)
	
	# Update scores and solids_player similar to runtime logic
	if balls_sunk[0] > 0 or balls_sunk[1] > 0:
		solids_player = 0
	
	if solids_player != -1:
		scores[solids_player] = balls_sunk[0]
		scores[1 - solids_player] = balls_sunk[1]
	else:
		scores = [balls_sunk[0], balls_sunk[1]]
	
	# Randomly position the visible balls on the table avoiding overlaps
	var placed_positions := []
	var x_min := -93.0
	var x_max := 93.0
	var z_min := -40.0
	var z_max := 40.0
	
	for i in range(sorted_balls.size()):
		var ball = sorted_balls[i]
		if ball == null or not ball.visible:
			continue
		
		var placed := false
		var attempts := 0
		var candidate := Vector3.ZERO
		
		while not placed and attempts < 200:
			attempts += 1
			var x := rng.randf_range(x_min, x_max)
			var z := rng.randf_range(z_min, z_max)
			candidate = Vector3(x, ball_radius, z)
		
			var ok := true
			for p in placed_positions:
				if p.distance_to(candidate) < min_spacing:
					ok = false
					break
		
			if ok:
				placed = true
				placed_positions.append(candidate)
				break
		
		# if we failed to find spaced pos, accept last candidate (or center fallback)
		if not placed:
			if attempts == 0:
				candidate = Vector3(0, ball_radius, 0)
			placed_positions.append(candidate)
		
		# apply placement
		ball.position = candidate

			
func init_break_triangle(x_shift: float, z_shift: float):
	var ball_ind: int = 0
	var ball_radius: float = 2.85
	var spacing: float = 1.05
	
	var colors = [
		[255, 215, 4], 
		[0, 0, 254], 
		[255, 0, 0], 
		[128, 0, 129], 
		[254, 165, 0], 
		[35, 139, 35], 
		[128, 0, 1],
		[0, 0, 0],
	]
	
	var ball_nums = range(1, 16)
	ball_nums.erase(8)
	ball_nums.shuffle()
	ball_nums.insert(4, 8)
	
	for i in range(5):
		for j in range(i + 1):
			var ball_node: Node = ball_scene.instantiate()
			var ball_num: int = ball_nums[ball_ind]
			ball_node.name = "Ball%s" % ball_num
			ball_node.ball_num = ball_num
			var x: float = x_shift + spacing * i * ball_radius * sqrt(3)
			var y: float = ball_radius
			var z: float = z_shift + (-i + 2 * j) * ball_radius * spacing
			ball_node.position = Vector3(x, y, z)
			
			color_ball(ball_node, ball_num, colors)
			balls.append(ball_node)
			add_child(ball_node)
			
			ball_ind += 1
	
func check_all_not_moving() -> bool:
	for ball in balls:
		if ball.is_visible() and (ball.get_linear_velocity().length() > speed_threshold \
		or ball.get_angular_velocity().length() > angular_speed_threshold):
			return false
	return true
	
func hide_cue_ball(ball) -> void:
	#print("Hiding cue ball, pos = " + str(ball.global_position))
	ball.global_position = Vector3(2000, 2000, 2000)
	ball.linear_velocity = Vector3(0, 0, 0)
	ball.angular_velocity = Vector3(0, 0, 0)
	ball.rotation = Vector3(0, 0, 0)
	ball.freeze = true
	cue_ball_potted = true
	cue_ball.hide()
	
func process_fallen_balls() -> void:
	var fallen_balls: Array[RigidBody3D] = find_fallen_balls()
	for ball in fallen_balls:
		process_fallen_ball(ball)

func find_fallen_balls() -> Array[RigidBody3D]:
	var fallen_balls: Array[RigidBody3D] = []
	for ball in balls:
		if ball.position.y < -10 and ball.visible:
			print(ball.name + " fell")
			fallen_balls.append(ball)
	return fallen_balls 
	
func process_fallen_ball(ball: RigidBody3D) -> void:
	if ball.is_cue_ball():
		hide_cue_ball(ball)
		ai_controller.reward -= 0.2
		ai_controller.cue_ball_sink_count += 1
		#if ai_controller.heuristic == 'model':
			#ai_controller.done = true
			#ai_controller.needs_reset = true
		return
		
	# 8 ball fell
	if ball.is_eight_ball():
		ai_controller.eight_ball_sunk = true
		# TODO: don't hardcode as solid
		if balls_sunk[0] == 7:
			add_to_ewma(true)
			ai_controller.reward += 10
		else:
			add_to_ewma(false)
			ai_controller.reward -= 10
		if scores[player_ind] == 7:
			scores[player_ind] += 1
		else:
			scores[player_ind] = -1000
		ai_controller.done = true
		ai_controller.needs_reset = true
	else:
		if ball.is_solid():
			balls_sunk[0] += 1
			ai_controller.reward += 1
		elif ball.is_stripe():
			balls_sunk[1] += 1
			ai_controller.reward -= 1
		
		if turn_num > 0 and solids_player == -1:
			if ball.is_solid():
				solids_player = player_ind
			elif ball.is_stripe():
				solids_player = 1 - player_ind
		
		if solids_player != -1:
			scores[solids_player] = balls_sunk[0]
			scores[1 - solids_player] = balls_sunk[1]
	
	#balls.erase(ball)
	#ball.queue_free()
	ball.hide()
	ball.collision_layer = 0
	ball.collision_mask = 0
	ball.set_freeze_enabled(true)
	
func reset_cue_ball(pos: Vector3) -> void:
	print("Resetting cue ball to pos: " + str(pos))
	cue_ball.teleport(pos)
	cue_ball_potted = false
	cue_ball.freeze = false
	cue_ball.show()
	cue_ball.linear_velocity = Vector3(0, 0, 0)
	game_state = GameState.AIMING
	
# TODO: if 8 ball is the only ball left, it is allowed
func check_for_first_hit_scratch() -> bool:
	var first_hit_ball_num = cue_ball.first_hit_ball_num 
	if first_hit_ball_num == -1:
		return false
	if solids_player == player_ind and not (1 <= first_hit_ball_num and first_hit_ball_num <= 7):
		return true
	if solids_player == 1 - player_ind and not (9 <= first_hit_ball_num and first_hit_ball_num <= 15):
		return true
	return false
	
func check_for_scratch():
	return cue_ball_potted #or check_for_first_hit_scratch()

func start_new_turn() -> void:
	if check_for_scratch():
		print("Scratch registered")
		game_state = GameState.PLACING
		if ai_controller.heuristic == 'model' or ai_controller.heuristic == "demo_record":
			reset_cue_ball(global_position + Vector3(-52, 3, 0))
			game_state = GameState.AIMING
	else:
		game_state = GameState.AIMING
	print("Starting new turn")
	turn_num += 1
	player_ind = 1 - player_ind
	cue_ball.first_hit_ball_num = -1
	ai_controller.increment_n_steps()

func _physics_process(delta: float) -> void:
	if (ai_controller.needs_reset):
		var sync = get_tree().get_nodes_in_group("SYNC")
		sync[0]._demo_record_process()
		
		ai_controller.reset()
		cue_ball.reset()
		start_game()
		return
	
	process_fallen_balls()
	
	if game_state == GameState.PLACING and ai_controller.heuristic == 'model':
		ai_controller.needs_reset = true
		ai_controller.done = true
		return
	elif game_state == GameState.MIDTURN:
		cue_stick.visible = false
		
	if check_all_not_moving():
		cur_static_ticks += 1
	else:
		game_state = GameState.MIDTURN
		cur_static_ticks = 0
	
	if game_state == GameState.MIDTURN and cur_static_ticks == static_ticks_threshold:
		if cue_ball.first_hit_ball_num <= 0:
			ai_controller.reward -= 0.2
		start_new_turn()
	
func fill_debug_label() -> void:
	var label_txt = "Static Ticks: " + str(cur_static_ticks)
	label_txt += "\nGame State: " + str(game_state)
	label_txt += "\nTurn Num: " + str(turn_num)
	label_txt += "\nCurrent Player Ind: " + str(player_ind)
	label_txt += "\nPlayer 0 Score: " + str(scores[0])
	label_txt += "\nPlayer 1 Score: " + str(scores[1])
	label_txt += "\nSolids Player: " + str(solids_player)
	label_txt += "\nSolids Sunk: " + str(balls_sunk[0])
	label_txt += "\nStripes Sunk: " + str(balls_sunk[1])
	label_txt += "\nFirst Hit: " + str(cue_ball.first_hit_ball_num)
	label_txt += "\nAI reward: " + str(ai_controller.reward)
	debug_label.text = label_txt

func _process(delta: float) -> void:
	fill_debug_label()
