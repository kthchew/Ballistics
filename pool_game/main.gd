extends Node3D

@onready var debug_label: Label = $UI/DebugLabel
@onready var info_label: Label = $UI/InfoLabel
@onready var slider = $UI/ForceSlider
@onready var fire_button = $UI/FireButton
@onready var aimer = $UI/Aimer
@onready var ai_controller = $AIController3D
@onready var camera = $CameraPivot/Camera3D
@onready var hole_buttons = $UI/HoleButtons
@onready var aim_visuals = $UI/AimVisuals
@onready var cue_stick = $UI/AimVisuals/CueStick
@onready var shape_cast = $ShapeCast3D
@onready var ball_manager = $BallManager
@onready var classical_ai = $ClassicalAI

enum GameState {AIMING, MIDTURN, PLACING, PICKPOCKET, ENDED}
const STATIC_TICKS_THRESHOLD: int = 60

var has_aimed := false
# physics defaults to 60 ticks per second
var static_ticks_threshold = 60
var cur_static_ticks = 0
var player_ind: int = 0
# TODO: score is unnecessary, just calculate as needed from balls_sunk[] and whether teams have been assigned
var scores: Array[int] = [0, 0]
var balls_sunk: Array[int] = [0, 0]
@export var game_state: GameState = GameState.AIMING
var turn_num: int = 0
var round_num: int = 0
var solids_player = -1
var next_solids_player = -1
var winner: int = -1
var play_again: bool = false
var target_hole: int = -1

const ball_scene = preload("res://ball.tscn")

var _ai_ewma_wins = 0.0
var _ai_games_played_current_stage = 0
var _ai_current_stage = 0

func _ready() -> void:
	
	ball_manager.init()
	aim_visuals.hide()
	$OverheadLight/Light.light_energy = 1000
	
	$UI/AimInputRegion.aim_changed.connect(_on_aim_changed)
	slider.value_changed.connect(_on_force_changed)
	fire_button.pressed.connect(_on_fire_pressed)
	hole_buttons.hole_selected.connect(_on_hole_selected)
	ball_manager.cue_ball.first_hit_ball_changed.connect(_on_first_hit_ball_changed)
	ball_manager.ball_sunk.connect(_on_ball_sunk)
	classical_ai.ai_aimed.connect(_on_ai_aimed)
	
	start_game()
	
	$OverheadLight/Light.light_energy = 1000
	
	ai_controller.init(self)
	ai_controller.fire.connect(_on_fire_pressed)

#func start_game() -> void: #old AI branch code
	#cur_static_ticks = 0
	#while balls.size() > 1:
		#balls[1].queue_free()
		#remove_child(balls[1])
		#balls.remove_at(1)
	#scores = [0, 0]
	#balls_sunk = [0, 0]
	#balls = []
	#balls.append(cue_ball)
	#init_break_triangle(56, 0)
	#if ai_controller.heuristic == 'model' and _ai_current_stage < 8:
		#var required_win_rate = 0.7 if _ai_current_stage > 0 else 0.9
		#shuffle_random_balls(_ai_current_stage, max(1, _ai_current_stage))
		#if _ai_ewma_wins > required_win_rate and _ai_games_played_current_stage > 100:
			#_ai_current_stage += 1
			#_ai_ewma_wins = 0
			#_ai_games_played_current_stage = 0
			#ai_controller.reset_after = max(5, _ai_current_stage * 10)
			
	#shuffle_random_balls(0, 0)
		#
	#cue_stick.visible = false
	#cue_ball_potted = false
	#game_state = GameState.AIMING
	#cue_ball.first_hit_ball_num = -1

func _on_aim_changed(touch_pos: Vector2):
	if game_state == GameState.MIDTURN or game_state == GameState.PICKPOCKET or game_state == GameState.ENDED:
		return
		
	if game_state == GameState.PLACING:
		var ray_origin = camera.project_ray_origin(touch_pos)
		var ray_normal = camera.project_ray_normal(touch_pos)
		var drop_plane = Plane(Vector3.UP, Vector3(0, Constants.BALL_RADIUS, 0))
		var intersection = drop_plane.intersects_ray(ray_origin, ray_normal)
		ball_manager.reset_cue_ball(intersection)
		start_round()
		return
		
	var ball_center_3d = ball_manager.get_cue_ball_global_pos()
	var ball_screen_pos = camera.unproject_position(ball_center_3d)
	var dir = ball_screen_pos - touch_pos
	if dir.length() < 20 or ball_manager.check_cue_ball_potted_by_pos():
		return
	aim(dir)
	
func _on_ai_aimed(dir: Vector2):
	aim(dir)
	slider.value = 50
	_on_force_changed(slider.value)
	await get_tree().create_timer(1.0).timeout
	_on_fire_pressed()
	
func aim(dir: Vector2):
	var ball_center_3d = ball_manager.get_cue_ball_global_pos()
	var ball_screen_pos = camera.unproject_position(ball_center_3d)
	has_aimed = true

	var angle = dir.angle()
	var dir_norm = dir.normalized()
	
	cast_aim_ray(dir_norm)

	var ball_edge_3d = ball_center_3d + Vector3(5, 0, 0)
	var center_screen = camera.unproject_position(ball_center_3d)
	var edge_screen = camera.unproject_position(ball_edge_3d)
	var ball_radius_px = (edge_screen - center_screen).length()
	var cue_pos = ball_screen_pos - dir_norm * ball_radius_px
	
	aim_visuals.show()
	cue_stick.show()
	cue_stick.update_position(ball_center_3d)
	cue_stick.set_angle(angle)

func _on_force_changed(value):
	var normalized = value / $UI/ForceSlider.max_value
	cue_stick.set_force_strength(normalized)
	
func calc_offset_3d(dir: Vector3, joy):
	var up = Vector3.UP
	if abs(dir.dot(up)) > 0.9:
		up = Vector3.FORWARD
		
	var right = dir.cross(up).normalized()
	var forward = right.cross(dir).normalized()

	var face_radius = 0.5
	var offset_3d = right * (joy.x * face_radius) + forward * (-joy.y * face_radius)
	return offset_3d
	
func calc_dir(angle):
	var dir = Vector3(cos(angle), 0, sin(angle)).normalized()
	return dir
	
func _on_fire_pressed():
	if game_state != GameState.AIMING or not has_aimed:
		return
		
	var sync = get_tree().get_nodes_in_group("SYNC")
	if sync[0].agent_demo_record:
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
	
	var dir = calc_dir(angle)
	var offset_3d = calc_offset_3d(dir, joy)
	var force = dir * (strength * 5)

	cue_stick.striking = true

	game_state = GameState.MIDTURN
	
	var tween := create_tween()

	var target_pos = ball_manager.get_cue_ball_global_pos() - cue_stick.aim_direction * Constants.BALL_RADIUS

	var distance = cue_stick.global_position.distance_to(target_pos)

	var base_speed = 20.0
	var scaled = pow(strength, 0.6)
	var speed = base_speed * (0.4 + 0.6 * scaled)

	var duration = distance / speed

	tween.tween_property(cue_stick, "global_position", target_pos, duration)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_IN_OUT)

	tween.tween_callback(func():
		#aim_visuals.hide()
		cue_stick.hide()
		cue_stick.striking = false
		ball_manager.hit_cue_ball(force, offset_3d)
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

func _on_first_hit_ball_changed():
	ball_manager.check_cue_ball_first_hit(player_ind, solids_player, scores)

func calc_hole_ind_from_pos(pos: Vector3) -> int:
	var hole_ind = 0
	if pos.z > 0:
		hole_ind += 3
	if pos.x > 50.91:
		hole_ind += 2
	elif pos.x > -50.91:
		hole_ind += 1
	return hole_ind
	
func _on_ball_sunk(ball):
	if ball.is_eight_ball():
		var hole_ind = calc_hole_ind_from_pos(ball.position)
		if scores[player_ind] >= Constants.BALLS_BEFORE_EIGHT and target_hole == hole_ind:
			end_game(player_ind)
		else:
			var sync = get_tree().get_nodes_in_group("SYNC")
			if sync[0].agent_demo_record:
				print("Removing really unsuccessful shot...")
				sync[0].current_demo_trajectory[0].pop_back()
				sync[0].current_demo_trajectory[1].pop_back()
			end_game(1 - player_ind)
	
	elif not ball.is_cue_ball():
		if solids_player == -1 \
		or (solids_player == player_ind and ball.is_solid()) \
		or (solids_player == 1 - player_ind and ball.is_stripe()):
			play_again = true
		
		if round_num > 0 and solids_player == -1:
			if ball.is_solid():
				next_solids_player = player_ind
			elif ball.is_stripe():
				next_solids_player = 1 - player_ind
		
		if next_solids_player != -1:
			scores[next_solids_player] = ball_manager.balls_sunk[0]
			scores[1 - next_solids_player] = ball_manager.balls_sunk[1]
	
func cast_aim_ray(aim_dir: Vector2) -> void:
	var origin = ball_manager.get_cue_ball_global_pos()
	var dir = Vector3(aim_dir.x, 0, aim_dir.y).normalized()
	
	shape_cast.global_position = origin
	shape_cast.max_results = 1
	shape_cast.target_position = 500 * dir
	shape_cast.collision_mask = 1 << 2
	
	shape_cast.force_shapecast_update()
	
	if not shape_cast.is_colliding():
		return
	
	var collider = shape_cast.get_collider(0)
		
	var collision_point = shape_cast.get_collision_point(0)
	var collision_normal = shape_cast.get_collision_normal(0).normalized()
	var aim_guide_line = $UI/AimVisuals/AimGuideLine
	var aim_guide_line2 = $UI/AimVisuals/AimGuideLine2
	
	var ghost_ball_pos = collision_point + collision_normal * Constants.BALL_RADIUS
	print("aim guide line ghost pos ", ghost_ball_pos)
	
	$UI/AimVisuals/AimGuideMarker.position = camera.unproject_position(ghost_ball_pos)
	$UI/AimVisuals/AimGuideCircle.position = camera.unproject_position(ghost_ball_pos)
	
	aim_guide_line.set_point_position(0, camera.unproject_position(origin))
	aim_guide_line.set_point_position(1, camera.unproject_position(ghost_ball_pos))
	
	aim_guide_line2.set_point_position(0, camera.unproject_position(ghost_ball_pos))
	
	var length = 500
	var normal_comp = dir.project(collision_normal)
	var surface_comp = dir - normal_comp
	
	var cue_ball_endpoint = ghost_ball_pos
	var object_ball_endpoint = ghost_ball_pos
	var hitting_ball = collider.name.contains("Ball")
	
	if hitting_ball and ball_manager.check_is_ball_valid(collider.ball_num, player_ind, solids_player, scores):
		cue_ball_endpoint = ghost_ball_pos + length * surface_comp
		object_ball_endpoint = ghost_ball_pos + length * normal_comp
	elif not hitting_ball:
		cue_ball_endpoint = ghost_ball_pos + length * (surface_comp - normal_comp)
		
	aim_guide_line.set_point_position(2, camera.unproject_position(cue_ball_endpoint))
	aim_guide_line2.set_point_position(1, camera.unproject_position(object_ball_endpoint))
	
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
		
func start_game() -> void:
	
	aim_visuals.hide()
	cue_stick.hide()
	has_aimed = false
	slider.value = 0
	cue_stick.set_force_strength(0.0)
	aimer._reset_knob()
	
	game_state = GameState.AIMING
	
	player_ind = 0
	cur_static_ticks = 0
	solids_player = -1
	next_solids_player = -1
	scores = [0, 0]
	turn_num = 0
	round_num = 0
	play_again = false
	target_hole = -1
	
	hole_buttons.hide()
	
	ball_manager.start_game()
	
	start_round()
	
func end_game(winner: int) -> void:
	self.winner = winner
	game_state = GameState.ENDED
	ball_manager.freeze_balls()
	#start_game()
	ai_controller.needs_reset = true
	process_midturn() #this is jank but should work
		
func start_round(scratched_prev: bool = false) -> void:
	if scratched_prev:
		if ball_manager.check_eight_ball_potted():
			end_game(player_ind)
		print("Scratch registered")
		#game_state = GameState.PLACING
		
		ball_manager.cue_ball.pot()
		ball_manager.reset_cue_ball(Vector3(-56, Constants.BALL_RADIUS, 0))
		#return
	#if target_hole == -1 and scores[player_ind] >= Constants.BALLS_BEFORE_EIGHT:
		#game_state = GameState.PICKPOCKET
		#hole_buttons.show()
		#return
		
	game_state = GameState.AIMING
		
	var agents = get_tree().get_nodes_in_group("AGENT")
	if len(agents) == 1 and agents[0].control_mode == agents[0].ControlModes.RECORD_EXPERT_DEMOS:
		classical_ai.find_shots(ball_manager.cue_ball, ball_manager.get_pottable_balls(player_ind, solids_player, scores))


func color_ball(ball_node: RigidBody3D, ball_num, colors) -> void:
	var mesh = ball_node.get_node("MeshInstance3D")
	var material: Material = StandardMaterial3D.new()
	
	ball_node.rotation = Vector3(0, 0, PI / 2)
	
	if ball_num > 8:
		var gradient: Gradient = Gradient.new()
		gradient.remove_point(0)
		gradient.remove_point(0)
		gradient.add_point(0.4, Color(1, 1, 1))
		gradient.add_point(0.4, Color(0, 0, 0))
		gradient.add_point(0.6, Color(0, 0, 0))
		gradient.add_point(0.6, Color(1, 1, 1))
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

#func shuffle_random_balls(solid_count: int, stripe_count: int) -> void:
	#var sorted_balls = balls
	#sorted_balls.sort_custom(func(a,b): return a.ball_num < b.ball_num)
	#var rng := RandomNumberGenerator.new()
	#rng.randomize()
	#
	#var total_solids := 7
	#var total_stripes := 7
	#var ball_radius := 2.85
	#var min_spacing := 6.0
	#
	## compute sunk counts and set state
	#balls_sunk[0] = total_solids - int(clamp(solid_count, 0, total_solids))
	#balls_sunk[1] = total_stripes - int(clamp(stripe_count, 0, total_stripes))
	#
	## pick which solid and stripe indices remain on table
	#var solid_indices := []
	#for i in range(1, 1 + total_solids):
		#solid_indices.append(i) # balls[1..7]
	#
	#var stripe_indices := []
	#for i in range(9, 9 + total_stripes):
		#stripe_indices.append(i) # balls[9..15]
	#
	#solid_indices.shuffle()
	#stripe_indices.shuffle()
	#
	#var solids_remaining := solid_indices.slice(0, clamp(solid_count, 0, total_solids))
	#var stripes_remaining := stripe_indices.slice(0, clamp(stripe_count, 0, total_stripes))
	#
	#var _in_list: Callable = func (val, arr):
		#for e in arr:
			#if e == val:
				#return true
		#return false
	
	# mark balls as hidden or visible based on selection
	#for i in range(sorted_balls.size()):
		#var ball = sorted_balls[i]
		#if ball == null:
			#continue
	#
		## solids 1..7
		#if i >= 1 and i <= 7:
			#if not _in_list.call(i, solids_remaining):
				## sink this ball
				#ball.hide()
				#ball.collision_layer = 0
				#ball.collision_mask = 0
				#ball.set_freeze_enabled(true)
	#
		## stripes 9..15
		#elif i >= 9 and i <= 15:
			#if not _in_list.call(i, stripes_remaining):
				#ball.hide()
				#ball.collision_layer = 0
				#ball.collision_mask = 0
				#ball.set_freeze_enabled(true)
	#
	## Update scores and solids_player similar to runtime logic
	#if balls_sunk[0] > 0 or balls_sunk[1] > 0:
		#solids_player = 0
	#
	#if solids_player != -1:
		#scores[solids_player] = balls_sunk[0]
		#scores[1 - solids_player] = balls_sunk[1]
	#else:
		#scores = [balls_sunk[0], balls_sunk[1]]
	#
	## Randomly position the visible balls on the table avoiding overlaps
	#var placed_positions := []
	#var x_min := -93.0
	#var x_max := 93.0
	#var z_min := -40.0
	#var z_max := 40.0
	#
	#for i in range(sorted_balls.size()):
		#var ball = sorted_balls[i]
		#if ball == null or not ball.visible:
			#continue
		#
		#var placed := false
		#var attempts := 0
		#var candidate := Vector3.ZERO
		#
		#while not placed and attempts < 200:
			#attempts += 1
			#var x := rng.randf_range(x_min, x_max)
			#var z := rng.randf_range(z_min, z_max)
			#candidate = Vector3(x, ball_radius, z)
		#
			#var ok := true
			#for p in placed_positions:
				#if p.distance_to(candidate) < min_spacing:
					#ok = false
					#break
		#
			#if ok:
				#placed = true
				#placed_positions.append(candidate)
				#break
		#
		## if we failed to find spaced pos, accept last candidate (or center fallback)
		#if not placed:
			#if attempts == 0:
				#candidate = Vector3(0, ball_radius, 0)
			#placed_positions.append(candidate)
		#
		## apply placement
		#ball.position = candidate

#func init_break_triangle(x_shift: float, z_shift: float):
	#var ball_ind: int = 0
	#var ball_radius: float = 2.85
	#var spacing: float = 1.05
	#
	#var colors = [
		#[255, 215, 4], 
		#[0, 0, 254], 
		#[255, 0, 0], 
		#[128, 0, 129], 
		#[254, 165, 0], 
		#[35, 139, 35], 
		#[128, 0, 1],
		#[0, 0, 0],
	#]
	#
	#var ball_nums = range(1, 16)
	#ball_nums.erase(8)
	#ball_nums.shuffle()
	#ball_nums.insert(4, 8)
	#
	#for i in range(5):
		#for j in range(i + 1):
			#var ball_node: Node = ball_scene.instantiate()
			#var ball_num: int = ball_nums[ball_ind]
			#ball_node.name = "Ball%s" % ball_num
			#ball_node.ball_num = ball_num
			#var x: float = x_shift + spacing * i * ball_radius * sqrt(3)
			#var y: float = ball_radius
			#var z: float = z_shift + (-i + 2 * j) * ball_radius * spacing
			#ball_node.position = Vector3(x, y, z)
			#
			#color_ball(ball_node, ball_num, colors)
			#
			#balls.append(ball_node)
			#add_child(ball_node)
			#
			#ball_ind += 1
	
#func check_all_not_moving() -> bool:
	#for ball in balls:
		#if ball.is_visible() and (ball.get_linear_velocity().length() > speed_threshold \
		#or ball.get_angular_velocity().length() > angular_speed_threshold):
			#return false
	#return true
	
#func hide_cue_ball(ball) -> void:
	##print("Hiding cue ball, pos = " + str(ball.global_position))
	#ball.global_position = Vector3(2000, 2000, 2000)
	#ball.linear_velocity = Vector3(0, 0, 0)
	#ball.angular_velocity = Vector3(0, 0, 0)
	#ball.rotation = Vector3(0, 0, 0)
	#ball.freeze = true
	#cue_ball_potted = true
	#cue_ball.hide()
	
#func process_fallen_balls() -> void:
	#var fallen_balls: Array[RigidBody3D] = find_fallen_balls()
	#for ball in fallen_balls:
		#process_fallen_ball(ball)

#func find_fallen_balls() -> Array[RigidBody3D]:
	#var fallen_balls: Array[RigidBody3D] = []
	#for ball in balls:
		#if ball.position.y < -10 and ball.visible:
			#print(ball.name + " fell")
			#fallen_balls.append(ball)
	#return fallen_balls 
	#
#func process_fallen_ball(ball: RigidBody3D) -> void:
	#if ball.is_cue_ball():
		#hide_cue_ball(ball)
		#ai_controller.reward -= 0.2
		#ai_controller.cue_ball_sink_count += 1
		##if ai_controller.heuristic == 'model':
			##ai_controller.done = true
			##ai_controller.needs_reset = true
		#return
		#
	## 8 ball fell
	#if ball.is_eight_ball():
		#ai_controller.eight_ball_sunk = true
		## TODO: don't hardcode as solid
		#if balls_sunk[0] == 7:
			#add_to_ewma(true)
			#ai_controller.reward += 10
		#else:
			#add_to_ewma(false)
			#ai_controller.reward -= 10
		#if scores[player_ind] == 7:
			#scores[player_ind] += 1
		#else:
			#scores[player_ind] = -1000
		#ai_controller.done = true
		#ai_controller.needs_reset = true
	#else:
		#if ball.is_solid():
			#balls_sunk[0] += 1
			#ai_controller.reward += 1
		#elif ball.is_stripe():
			#balls_sunk[1] += 1
			#ai_controller.reward -= 1
		#
		#if turn_num > 0 and solids_player == -1:
			#if ball.is_solid():
				#solids_player = player_ind
			#elif ball.is_stripe():
				#solids_player = 1 - player_ind
		#
		#if solids_player != -1:
			#scores[solids_player] = balls_sunk[0]
			#scores[1 - solids_player] = balls_sunk[1]
	#
	#balls.erase(ball)
	#ball.queue_free()
	#ball.hide()
	#ball.collision_layer = 0
	#ball.collision_mask = 0
	#ball.set_freeze_enabled(true)
	
#func reset_cue_ball(pos: Vector3) -> void:
	#print("Resetting cue ball to pos: " + str(pos))
	#cue_ball.teleport(pos)
	#cue_ball_potted = false
	#cue_ball.freeze = false
	#cue_ball.show()
	#cue_ball.linear_velocity = Vector3(0, 0, 0)
	#game_state = GameState.AIMING
	
# TODO: if 8 ball is the only ball left, it is allowed
#func check_for_first_hit_scratch() -> bool:
	#var first_hit_ball_num = cue_ball.first_hit_ball_num 
	#if first_hit_ball_num == -1:
		#return false
	#if solids_player == player_ind and not (1 <= first_hit_ball_num and first_hit_ball_num <= 7):
		#return true
	#if solids_player == 1 - player_ind and not (9 <= first_hit_ball_num and first_hit_ball_num <= 15):
		#return true
	#return false
	
#func check_for_scratch():
	#return cue_ball_potted or check_for_first_hit_scratch()

func end_round() -> void:
	ai_controller.increment_n_steps()
	if ((solids_player != -1 and ball_manager.balls_sunk[int(player_ind != solids_player)] == ball_manager.prev_sunk[int(player_ind != solids_player)])
	or (solids_player == -1 and ball_manager.balls_sunk[0] == ball_manager.prev_sunk[0] and ball_manager.balls_sunk[1] == ball_manager.prev_sunk[1])):
		var sync = get_tree().get_nodes_in_group("SYNC")
		if sync[0].agent_demo_record:
			print("Removing unsuccessful shot...")
			sync[0].current_demo_trajectory[0].pop_back()
			sync[0].current_demo_trajectory[1].pop_back()
	ball_manager.prev_sunk = ball_manager.balls_sunk.duplicate()
	
	round_num += 1
	
	target_hole = -1
	if next_solids_player != -1:
		solids_player = next_solids_player
	
	var scratched = ball_manager.check_scratch()
	ball_manager.end_round()
	
	if not scratched and play_again:
		play_again = false
		start_round()
		return
	
	play_again = false
	turn_num += 1
	player_ind = 1 - player_ind
	start_round(scratched)

func process_midturn():
	ball_manager.process_fallen_balls()
	process_movement()
	
	if (ai_controller.needs_reset):
		ai_controller.done = true #guarantees "terminal" branch in sync node?
		var sync = get_tree().get_nodes_in_group("SYNC")
		if sync[0].agent_demo_record:
			sync[0]._demo_record_process()
		
		ai_controller.reset()
		start_game()
		return
	

func process_movement():
	if ball_manager.check_all_not_moving():
		cur_static_ticks += 1
	else:
		cur_static_ticks = 0
		
	if cur_static_ticks == STATIC_TICKS_THRESHOLD:
		#if cue_ball.first_hit_ball_num <= 0:
			#ai_controller.reward -= 0.2	
		end_round()

func _physics_process(delta: float) -> void:
	if game_state != GameState.MIDTURN:
		return
	process_midturn()
		
func _process(delta: float) -> void:
	fill_debug_label()
	fill_info_label()
	
	
func fill_debug_label() -> void:
	var label_txt = "Static Ticks: " + str(cur_static_ticks)
	
	label_txt += "\n\nGame State: " + str(game_state)
	label_txt += "\nTurn Num: " + str(turn_num)
	label_txt += "\nRound Num: " + str(round_num)
	label_txt += "\nPlay Again: " + str(play_again)
	
	label_txt += "\n\nCurrent Player Ind: " + str(player_ind)
	label_txt += "\nSolids Player: " + str(solids_player)
	label_txt += "\nNext Solids Player: " + str(next_solids_player)
	label_txt += "\nPlayer 0 Score: " + str(scores[0])
	label_txt += "\nPlayer 1 Score: " + str(scores[1])
	
	label_txt += "\n\nSolids Sunk: " + str(ball_manager.balls_sunk[0])
	label_txt += "\nStripes Sunk: " + str(ball_manager.balls_sunk[1])
	label_txt += "\nFirst Hit: " + str(ball_manager.cue_ball.first_hit_ball_num)
	label_txt += "\nFirst Hit Scratch: " + str(ball_manager.first_hit_scratch)
	
	label_txt += "\nAI reward: " + str(ai_controller.reward)
	debug_label.text = label_txt

func fill_info_label() -> void:
	info_label.text = ""
	
	if game_state == GameState.ENDED:
		info_label.text = "Player " + str(winner + 1) + " won the game! Click the 'Reset Game' button to play again"
	
	if game_state != GameState.MIDTURN and game_state != GameState.ENDED:
		info_label.text += "Player " + str(player_ind + 1) + "'s turn.\n"
		if scores[player_ind] < Constants.BALLS_BEFORE_EIGHT:
			if player_ind == solids_player:
				info_label.text += "You are solids\n"
			elif 1 - player_ind == solids_player:
				info_label.text += "You are stripes\n"
	
	if game_state == GameState.PICKPOCKET:
		info_label.text += "Pick your target pocket for the 8-ball\n"
			
	if game_state == GameState.PLACING:
		info_label.text += "Your opponent scratched, click to place the cue ball\n"
