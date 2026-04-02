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
@onready var ball_manager = $BallManager

enum GameState {AIMING, MIDTURN, PLACING, PICKPOCKET, ENDED, NOT_STARTED}
const STATIC_TICKS_THRESHOLD: int = 60

var init_peer = null
var has_aimed := false
# physics defaults to 60 ticks per second
var cur_static_ticks = 0

@export var lobby_slot: int = -1
@export var player_ind: int = 0
@export var scores: Array[int] = [0, 0]
@export var game_state: GameState = GameState.NOT_STARTED
@export var turn_num: int = 0
@export var round_num: int = 0
@export var solids_player = -1
@export var next_solids_player = -1
@export var winner: int = -1
@export var play_again: bool = false
@export var target_hole: int = -1
@export var connected_peers = [-1, -1] # index is player index, value is peer id

const ball_scene = preload("res://ball.tscn")
const ball_script = preload("res://ball.gd")
const ball_shape = preload("res://ball_shape.tres")

func _ready() -> void:
	if init_peer != null:
		multiplayer.multiplayer_peer = init_peer
	
	aim_visuals.hide()
	$OverheadLight/Light/AudioStreamPlayer3D.play(0.0)
	await get_tree().create_timer(0.25).timeout
	$OverheadLight/Light.light_energy = 1000
	$UI.visible = true
	
	$UI/AimInputRegion.aim_changed.connect(_on_aim_changed.rpc)
	slider.value_changed.connect(_on_force_changed.rpc)
	fire_button.pressed.connect(_on_fire_pressed)
	hole_buttons.hole_selected.connect(_on_hole_selected.rpc)
		
	ball_manager.cue_ball.first_hit_ball_changed.connect(_on_first_hit_ball_changed)
	ball_manager.ball_sunk.connect(_on_ball_sunk)
	
	ball_manager.init()
	
	$MultiplayerSynchronizer.set_visibility_for(1, true)
	if connected_peers[0] != -1 and connected_peers[1] != -1:
		start_game()
	
func calc_offset_3d(dir: Vector3):
	var up = Vector3.UP
	if abs(dir.dot(up)) > 0.9:
		up = Vector3.FORWARD
		
	var right = dir.cross(up).normalized()
	var forward = right.cross(dir).normalized()

	var face_radius = 0.5
	var joy = aimer.output
	var offset_3d = right * (joy.x * face_radius) + forward * (-joy.y * face_radius)
	return offset_3d
	
func calc_dir():
	var angle = cue_stick.angle
	var dir = Vector3(cos(angle), 0, sin(angle)).normalized()
	return dir

@rpc
func change_hole_button_visibility(is_visible: bool) -> void:
	hole_buttons.visible = is_visible

@rpc("any_peer", "reliable")
func _on_hole_selected(hole_ind: int) -> void:
	if not multiplayer.is_server() or connected_peers[player_ind] != multiplayer.get_remote_sender_id() or game_state != GameState.PICKPOCKET:
		return
	target_hole = hole_ind
	change_hole_button_visibility.rpc_id(multiplayer.get_remote_sender_id(), false)
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
	
@rpc
func cast_aim_ray(aim_dir: Vector2) -> void:
	var origin = ball_manager.get_cue_ball_global_pos()
	var dir = Vector3(aim_dir.x, 0, aim_dir.y).normalized()
	
	shape_cast.global_position = origin
	shape_cast.max_results = 1
	shape_cast.target_position = 500 * dir
	shape_cast.collision_mask = 1 << 2
	shape_cast.collide_with_areas = true
	
	shape_cast.force_shapecast_update()
	
	if not shape_cast.is_colliding():
		return
	
	var collider = shape_cast.get_collider(0)
		
	var collision_point = shape_cast.get_collision_point(0)
	var collision_normal = shape_cast.get_collision_normal(0).normalized()
	var aim_guide_line = $UI/AimVisuals/AimGuideLine
	var aim_guide_line2 = $UI/AimVisuals/AimGuideLine2
	
	var ghost_ball_pos = collision_point + collision_normal * Constants.BALL_RADIUS
	
	$UI/AimVisuals/AimGuideMarker.position = camera.unproject_position(ghost_ball_pos)
	$UI/AimVisuals/AimGuideCircle.position = camera.unproject_position(ghost_ball_pos)
	
	aim_guide_line.set_point_position(0, camera.unproject_position(origin))
	aim_guide_line.set_point_position(1, camera.unproject_position(ghost_ball_pos))
	
	aim_guide_line2.set_point_position(0, camera.unproject_position(ghost_ball_pos))
	
	var length = 20
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

@rpc("authority", "call_local")
func set_visibility():
	print("setting visibility")
	if connected_peers[0] != -1:
		$MultiplayerSynchronizer.set_visibility_for(connected_peers[0], true)
	if connected_peers[1] != -1:
		$MultiplayerSynchronizer.set_visibility_for(connected_peers[1], true)
	
func start_game() -> void:
	set_visibility.rpc()
	
	aim_visuals.hide()
	cue_stick.hide()
	hole_buttons.hide()
	
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
	
	ball_manager.start_game()
			

@rpc("any_peer", "reliable")
func _on_aim_changed(touch_pos: Vector2):
	if not multiplayer.is_server() or connected_peers[player_ind] != multiplayer.get_remote_sender_id():
		return
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
		
	has_aimed = true

	var angle = dir.angle()
	var dir_norm = dir.normalized()
	
	cast_aim_ray.rpc_id(multiplayer.get_remote_sender_id(), dir_norm)

	var ball_edge_3d = ball_center_3d + Vector3(5, 0, 0)
	var center_screen = camera.unproject_position(ball_center_3d)
	var edge_screen = camera.unproject_position(ball_edge_3d)
	var ball_radius_px = (edge_screen - center_screen).length()
	var cue_pos = ball_screen_pos - dir_norm * ball_radius_px
	
	cue_stick.update_position(ball_center_3d)
	cue_stick.set_angle(angle)
	aim_visuals.show()
	cue_stick.show()

@rpc("any_peer", "reliable")
func _on_force_changed(value):
	if not multiplayer.is_server() or connected_peers[player_ind] != multiplayer.get_remote_sender_id():
		return
	var normalized = value / $UI/ForceSlider.max_value
	cue_stick.set_force_strength(normalized)
	
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
	
func _on_fire_pressed():
	# need to set the strength in case it was changed by other player's turn
	_on_force_changed.rpc_id(1, slider.value)
	fire_cue.rpc_id(1)
	
@rpc("any_peer", "reliable")
func fire_cue():
	if not multiplayer.is_server() \
	   or connected_peers[player_ind] != multiplayer.get_remote_sender_id() \
	   or game_state != GameState.AIMING \
	   or not has_aimed:
		return
	
	var dir = calc_dir()
	var offset_3d = calc_offset_3d(dir)
	var strength = slider.value
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
		aim_visuals.hide()
		cue_stick.hide()
		cue_stick.striking = false
		ball_manager.hit_cue_ball(force, offset_3d)
	)
	print("STRENGTH:", strength)
	ball_manager.play_cue_ball_sound(strength)

	if strength > 95.0:
		shake_camera(0.5, 0.1)
		sway_light(7, 7)

	has_aimed = false
	slider.value = 0
	cue_stick.set_force_strength(0.0)
	aimer._reset_knob()
	
func end_game(winner: int) -> void:
	self.winner = winner
	game_state = GameState.ENDED
	ball_manager.freeze_balls()
		
func start_round(scratched_prev: bool = false) -> void:
	if scratched_prev:
		if ball_manager.check_eight_ball_potted():
			end_game(player_ind)
		print("Scratch registered")
		game_state = GameState.PLACING
		ball_manager.cue_ball.pot()
		return
	
	if target_hole == -1 and scores[player_ind] >= Constants.BALLS_BEFORE_EIGHT:
		game_state = GameState.PICKPOCKET
		change_hole_button_visibility.rpc_id(connected_peers[player_ind], true)
		return
	
	game_state = GameState.AIMING
	
func end_round() -> void:
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
	if multiplayer.is_server():
		if game_state != GameState.MIDTURN:
			return
		else:
			cue_stick.visible = false
			
		ball_manager.process_fallen_balls()
		process_movement()

func process_movement():
	if ball_manager.check_all_not_moving():
		cur_static_ticks += 1
	else:
		cur_static_ticks = 0
		
	if cur_static_ticks == STATIC_TICKS_THRESHOLD:
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
	
	debug_label.text = label_txt

func fill_info_label() -> void:
	var is_your_turn = connected_peers[player_ind] == multiplayer.get_unique_id()
	info_label.text = ""
	
	if game_state == GameState.NOT_STARTED:
		info_label.text = "Currently waiting for enough players..."
	
	if game_state == GameState.ENDED:
		info_label.text = "Player " + str(winner + 1) + " won the game! Click the 'Reset Game' button to play again"
	
	if game_state != GameState.MIDTURN and game_state != GameState.ENDED and game_state != GameState.NOT_STARTED:
		if multiplayer.is_server():
			info_label.text += "Player " + str(player_ind + 1) + "'s turn.\n"
		elif is_your_turn:
			info_label.text += "Your turn.\n"
		else:
			info_label.text += "Opponent's turn.\n"
		if solids_player != -1 and scores[player_ind] < Constants.BALLS_BEFORE_EIGHT:
			if connected_peers[solids_player] == multiplayer.get_unique_id():
				info_label.text += "You are solids\n"
			else:
				info_label.text += "You are stripes\n"
	
	if is_your_turn:
		if game_state == GameState.PICKPOCKET:
			info_label.text += "Pick your target pocket for the 8-ball\n"
				
		if game_state == GameState.PLACING:
			info_label.text += "Your opponent scratched, click to place the cue ball\n"
