extends Node3D

@onready var debug_label: Label = $LabelLayer/DebugLabel
@onready var info_label: Label = $LabelLayer/InfoLabel
@onready var slider = $UI/ForceSlider
@onready var fire_button = $UI/FireButton
@onready var aimer = $UI/Aimer
@onready var camera = $CameraPivot/Camera3D
@onready var hole_buttons = $UI/HoleButtons
@onready var aim_visuals = $UI/AimVisuals
@onready var aim_guide = $UI/AimVisuals/AimGuide
@onready var cue_stick = $UI/AimVisuals/CueStick
@onready var reroll_button: Button = $pUI/Panel/HBoxContainer2/RerollButton
@onready var shape_cast = $ShapeCast3D
@onready var ball_manager = $BallManager
@onready var cashout = false

var game_type: Utils.GameType = Utils.GameType.EIGHT_BALL_MULTIPLAYER
enum GameState {AIMING, MIDTURN, PLACING, PICKPOCKET, ENDED, CRAZY, NOT_STARTED, CASHOUT}
var cashout_owner_ind: int = -1
var local_cashout_owner: bool = false
var continue_after_crazy: bool = false
const POWER_BASE_COSTS := {"block": 5, "tungsten": 8, "tnt": 10}
const POWER_COST_VARIATION_PERCENT: int = 10
var power_shop_options: Array[String] = []
var power_shop_costs: Dictionary = {}
var power_shop_used: Array[String] = []
const STATIC_TICKS_THRESHOLD: int = 60

var init_peer = null
var has_aimed := false
# physics defaults to 60 ticks per second
var cur_static_ticks = 0
var requesting_reset: Array[bool] = [false, false] # index is player index


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
@export var connected_peers = [-1, -1]
@export var money = [0,0]

var first_hit_scratch: bool = false
const ball_scene = preload("res://Scenes/ball.tscn")
const ball_script = preload("res://Scripts/ball.gd")
const ball_shape = preload("res://ball_shape.tres")

func _ready() -> void:
	$CashOut/Panel/VBoxContainer/HBoxContainer/Yes.pressed.connect(_on_yes_pressed_local)
	$CashOut/Panel/VBoxContainer/HBoxContainer/No.pressed.connect(_on_no_pressed_local)
	print("MAIN READY PATH:", get_path(), "\nGAME TYPE:", game_type)
	if init_peer != null:
		multiplayer.multiplayer_peer = init_peer
	
	aim_visuals.hide()
	
	$UI/AimInputRegion.aim_changed.connect(_on_aim_input)
	slider.value_changed.connect(_on_force_changed.rpc)
	fire_button.pressed.connect(_on_fire_pressed)
	hole_buttons.hole_selected.connect(_on_hole_selected.rpc)
	
	ball_manager.init()
	
	ball_manager.cue_ball.first_hit_ball_changed.connect(_on_first_hit_ball_changed)
	ball_manager.ball_sunk.connect(_on_ball_sunk)
	
	$MultiplayerSynchronizer.set_visibility_for(1, true)
	if connected_peers[0] != -1 and connected_peers[1] != -1:
		start_game()
		
	turn_on_light()
	
func turn_on_light():
	$OverheadLight/Light/AudioStreamPlayer3D.play(0.0)
	await get_tree().create_timer(0.25).timeout
	$OverheadLight/Light.light_energy = 1000
	$UI.visible = true
	$LabelLayer.visible = true
	
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
func change_hole_button_visibility(visible_state: bool) -> void:
	hole_buttons.visible = visible_state

@rpc("any_peer", "reliable")
func _on_hole_selected(hole_ind: int) -> void:
	if not multiplayer.is_server() or connected_peers[player_ind] != multiplayer.get_remote_sender_id() or game_state != GameState.PICKPOCKET:
		return
	target_hole = hole_ind
	change_hole_button_visibility.rpc_id(multiplayer.get_remote_sender_id(), false)
	start_round()

func _on_reset_button_pressed() -> void:
	reset_request.rpc_id(1)
	reset_request.rpc_id(connected_peers[0])
	reset_request.rpc_id(connected_peers[1])
	
@rpc("any_peer", "call_local")
func reset_request() -> void:
	var sender = multiplayer.get_remote_sender_id()
	var changer_ind = connected_peers.find(sender) if sender != 0 else connected_peers.find(multiplayer.get_unique_id())
	var this_ind = connected_peers.find(multiplayer.get_unique_id())
	
	requesting_reset[changer_ind] = not requesting_reset[changer_ind]
	$UI/ResetButton/ResetRequestedLabel.visible = requesting_reset[changer_ind]
	
	if requesting_reset[this_ind]:
		$UI/ResetButton/ResetRequestedLabel.text = "Requested reset"
	else:
		$UI/ResetButton/ResetRequestedLabel.text = "Opponent requested reset"
	
	if requesting_reset[0] and requesting_reset[1]:
		if multiplayer.is_server():
			start_game()
		$UI/ResetButton/ResetRequestedLabel.visible = false
		requesting_reset = [false, false]

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
	if not multiplayer.is_server():
			return
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
		
		if ball.is_solid() and player_ind == solids_player:
			money[1 - player_ind] += 10
			
		elif ball.is_stripe() and player_ind != solids_player and solids_player != -1:
			money[1 - player_ind] += 10
	update_money_all.rpc(money)
	
func cast_aim_ray(aim_dir: Vector2) -> void:
	var origin = ball_manager.get_cue_ball_global_pos()
	var dir = Vector3(aim_dir.x, 0, aim_dir.y).normalized()
	shape_cast.global_position = origin
	shape_cast.max_results = 1
	shape_cast.target_position = 500 * dir
	shape_cast.collision_mask = (1 << 2) | (1 << 3)
	shape_cast.collide_with_areas = true
	shape_cast.force_shapecast_update()
	if not shape_cast.is_colliding():
		return
	var collider = shape_cast.get_collider(0)
	var collision_point = shape_cast.get_collision_point(0)
	var collision_normal = shape_cast.get_collision_normal(0).normalized()
	var aim_guide_line = $UI/AimVisuals/AimGuide/AimGuideLine
	var aim_guide_line2 = $UI/AimVisuals/AimGuide/AimGuideLine2
	
	var ghost_ball_pos = collision_point + collision_normal * Constants.BALL_RADIUS
	
	$UI/AimVisuals/AimGuide/AimGuideMarker.position = camera.unproject_position(ghost_ball_pos)
	$UI/AimVisuals/AimGuide/AimGuideCircle.position = camera.unproject_position(ghost_ball_pos)
	
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
	set_visibility()
	set_visibility.rpc_id(connected_peers[0])
	set_visibility.rpc_id(connected_peers[1])
	
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
	money = [0, 0]
	turn_num = 0
	round_num = 0
	play_again = false
	target_hole = -1
	
	requesting_reset = [false, false]
	
	ball_manager.start_game()
			
func _on_aim_input(touch_pos: Vector2):
	if not is_your_turn():
		return
	if game_state == GameState.PLACING:
		var ray_origin: Vector3 = camera.project_ray_origin(touch_pos)
		var ray_normal: Vector3 = camera.project_ray_normal(touch_pos)
		var drop_plane: Plane = Plane(Vector3.UP, Vector3(0, Constants.BALL_RADIUS, 0))
		var intersection = drop_plane.intersects_ray(ray_origin, ray_normal)
		if intersection == null:
			return
		_on_place_cue_ball.rpc_id(1, intersection)
	elif game_state == GameState.AIMING:
		# calculate difference between cue ball position and touch pos, use that to set cue stick angle
		# this is done so that the vector provided to the server is consistent even if the window's size or aspect ratio is different
		var ball_center_3d = ball_manager.get_cue_ball_global_pos()
		var ball_screen_pos: Vector2 = camera.unproject_position(ball_center_3d)
		var dir: Vector2 = ball_screen_pos - touch_pos
		if dir.length() >= 20:
			var other_peer = connected_peers[1 - player_ind]
			_on_aim_changed(dir)
			cast_aim_ray(dir.normalized())
			aim_visuals.show()
			aim_guide.show()
			_on_aim_changed.rpc_id(1, dir)
			_on_aim_changed.rpc_id(other_peer, dir)

@rpc("any_peer")
func _on_place_cue_ball(place_global_pos: Vector3):
	if not multiplayer.is_server() or connected_peers[player_ind] != multiplayer.get_remote_sender_id() or game_state != GameState.PLACING:
		return
	ball_manager.reset_cue_ball(place_global_pos)
	start_round()

@rpc("any_peer", "reliable")
func _on_aim_changed(dir_from_cue: Vector2):
	if (multiplayer.get_remote_sender_id() != 0 and connected_peers[player_ind] != multiplayer.get_remote_sender_id()) or game_state != GameState.AIMING:
		return

	var ball_center_3d = ball_manager.get_cue_ball_global_pos()
	
	if dir_from_cue.length() < 20 or ball_manager.check_cue_ball_potted_by_pos():
		return
	has_aimed = true

	var angle: float = dir_from_cue.angle()
	
	cue_stick.update_position(ball_center_3d)
	cue_stick.set_angle(angle)
	cue_stick.show()

@rpc("any_peer", "reliable")
func _on_force_changed(value):
	if not multiplayer.is_server() or connected_peers[player_ind] != multiplayer.get_remote_sender_id():
		return
	var normalized = value / $UI/ForceSlider.max_value
	cue_stick.set_force_strength(normalized)

func shake_camera(intensity: float, duration: float) -> void:
	var cam := $CameraPivot/Camera3D
	var original :Vector3 = cam.rotation_degrees
	var tween := create_tween()
	tween.tween_property(cam, "rotation_degrees", original + Vector3(intensity, intensity, intensity), duration / 2)
	tween.set_trans(Tween.TRANS_SINE)  # Set transition type to sine for smoothness
	tween.set_ease(Tween.EASE_OUT)     # Set easing type to ease out for dampening
	tween.tween_property(cam, "rotation_degrees", original, duration / 2)

func sway_light(amount: float, duration: float) -> void:
	var light := $OverheadLight/Light
	var tween := create_tween()
	var original_rot : Vector3 = light.rotation
	var cycles := 6
	var cycle_time := duration / cycles
	for i in range(cycles):
		var amp := deg_to_rad(amount * pow(0.55, i))
		var target_rot : Vector3 = original_rot + Vector3(0, amp, 0)
		tween.tween_property(light, "rotation", target_rot, cycle_time * 0.5)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var opposite_rot : Vector3 = original_rot - Vector3(0, amp, 0)
		tween.tween_property(light, "rotation", opposite_rot, cycle_time * 0.5)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(light, "rotation", original_rot, cycle_time * 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
func _on_fire_pressed():
	if not is_your_turn() or game_state != GameState.AIMING:
		return
	if slider.value == 0:
		slider.wiggle()
		return
	# need to set the strength in case it was changed by other player's turn
	_on_force_changed.rpc_id(1, slider.value)
	fire_cue.rpc_id(1)
	aim_guide.hide()
	
	has_aimed = false
	slider.value = 0
	cue_stick.set_force_strength(0.0)
	aimer._reset_knob()
	
@rpc("any_peer", "reliable")
func fire_cue():
	if not multiplayer.is_server() or connected_peers[player_ind] != multiplayer.get_remote_sender_id() or game_state != GameState.AIMING or not has_aimed:
		return
	
	var dir = calc_dir()
	var offset_3d = calc_offset_3d(dir)
	var strength = cue_stick.strength * 100
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
		aim_guide.hide()
		cue_stick.hide()
		cue_stick.striking = false
		ball_manager.hit_cue_ball(force, offset_3d)
	)
	print("STRENGTH:", strength)
	ball_manager.play_cue_ball_sound(strength)

	if strength > 95.0:
		shake_camera(0.5, 0.1)
		sway_light(7, 7)
	
func end_game(winning_player: int) -> void:
	self.winner = winning_player
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
	
func update_cashout_label() -> void:
	var owner_money_text = "Money: ?"
	var owner_index = cashout_owner_ind
	if owner_index == -1:
		owner_index = get_local_player_index()
	if owner_index >= 0 and owner_index < money.size():
		owner_money_text = "Money: " + str(money[owner_index])
	$CashOut/Panel/VBoxContainer/Label.text = "Cashout decision\n" + owner_money_text + "\nDo you want to cash out?"

@rpc("any_peer", "reliable")
func show_cashout_wait_menu(owner_peer_id: int) -> void:
	if multiplayer.get_unique_id() == owner_peer_id:
		return
	game_state = GameState.CASHOUT
	$UI.visible = false

@rpc("any_peer", "reliable")
func restore_ui_after_cashout() -> void:
	$UI.visible = true

@rpc("any_peer", "reliable")
func set_cashout_owner(owner_index: int) -> void:
	cashout_owner_ind = owner_index

@rpc("any_peer", "reliable")
func show_cashout_menu(server_money: Array, owner_index: int) -> void:
	local_cashout_owner = true
	cashout_owner_ind = owner_index
	money = server_money.duplicate()
	game_state = GameState.CASHOUT
	$UI.visible = false
	$CashOut.visible = true
	update_cashout_label()
	$pUI.visible = false
	
func end_round() -> void:
	round_num += 1
	target_hole = -1
	money[0] += 1
	money[1] += 1
	if next_solids_player != -1:
		solids_player = next_solids_player
	var scratched = ball_manager.check_scratch()
	ball_manager.end_round()
	if continue_after_crazy:
		continue_after_crazy = false
		play_again = false
		start_round(scratched)
		return
	if not scratched and play_again:
		if solids_player != -1 and game_type == Utils.GameType.CRAZY_EIGHT_BALL_MULTIPLAYER:
			cashout = true
			cashout_owner_ind = 1 - player_ind
			set_cashout_owner.rpc(cashout_owner_ind)
			var cashout_peer_id = connected_peers[cashout_owner_ind]
			if cashout_peer_id != -1:
				game_state = GameState.CASHOUT
				show_cashout_wait_menu.rpc(cashout_peer_id)
				if cashout_peer_id == multiplayer.get_unique_id():
					show_cashout_menu(money, cashout_owner_ind)
				else:
					show_cashout_menu.rpc_id(cashout_peer_id, money, cashout_owner_ind)
			return
		else:
			play_again = false
			start_round(scratched)
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
	if $pUI and $pUI.visible:
		update_powerup_shop()

func is_your_turn() -> bool:
	if connected_peers and connected_peers.size() > player_ind:
		return connected_peers[player_ind] == multiplayer.get_unique_id()
	return false
	
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
	
	if game_type == Utils.GameType.CRAZY_EIGHT_BALL_MULTIPLAYER:
		label_txt += "\nStripes Crazy Currency: " + str(money[0])
		label_txt += "\nSolids Crazy Currency: " + str(money[1])
	debug_label.text = label_txt

func get_cashout_owner_peer_id() -> int:
	if cashout_owner_ind < 0 or cashout_owner_ind >= connected_peers.size():
		return -1
	return connected_peers[cashout_owner_ind]

func is_local_cashout_owner() -> bool:
	return get_cashout_owner_peer_id() == multiplayer.get_unique_id()

func fill_info_label() -> void:
	info_label.text = ""
	if game_state == GameState.NOT_STARTED:
		info_label.text = "Currently waiting for enough players..."
	if game_state == GameState.ENDED:
		info_label.text = "Player " + str(winner + 1) + " won the game! Click the 'Reset Game' button to play again"
	if game_state == GameState.CASHOUT:
		if is_local_cashout_owner():
			info_label.text += "Decide whether to cash out and use power ups.\n"
		else:
			info_label.text += "Opponent is deciding whether to cash out.\n"
	if game_state != GameState.MIDTURN and game_state != GameState.ENDED and game_state != GameState.NOT_STARTED:
		if multiplayer.is_server():
			info_label.text += "Player " + str(player_ind + 1) + "'s turn.\n"
		elif is_your_turn():
			info_label.text += "Your turn.\n"
		else:
			info_label.text += "Opponent's turn.\n"
		if solids_player != -1 and scores[player_ind] < Constants.BALLS_BEFORE_EIGHT:
			if connected_peers[solids_player] == multiplayer.get_unique_id():
				info_label.text += "You are solids\n"
			else:
				info_label.text += "You are stripes\n"
	
	if is_your_turn():
		if game_state == GameState.PICKPOCKET:
			info_label.text += "Pick your target pocket for the 8-ball\n"
		if game_state == GameState.PLACING:
			info_label.text += "Your opponent scratched, click to place the cue ball\n"

func _on_no_pressed() -> void:
	local_cashout_owner = false
	$CashOut.visible = false
	$UI.visible = true
	cashout = false
	end_round()
	
@onready var objects = 0
var randPower = []

func _on_yes_pressed() -> void:
	local_cashout_owner = false
	game_state = GameState.CRAZY
	$CashOut.visible = false
	$pUI.visible = true
	initialize_powerup_shop()
	update_powerup_shop()

func _on_done_powerup_pressed() -> void:
	$pUI.visible = false
	$UI.visible = true
	request_finish_powerup_selection.rpc()

func _on_reroll_powerup_pressed() -> void:
	if get_local_player_money() < 1:
		return
	var local_index = get_local_player_index()
	if local_index == -1:
		return
	money[local_index] -= 1
	initialize_powerup_shop()
	update_powerup_shop()

func initialize_powerup_shop() -> void:
	if objects > 0:
		power_shop_options = ["block", "tungsten", "tnt"]
	else:
		power_shop_options = ["block", "tungsten"]
	power_shop_options.shuffle()
	power_shop_used.clear()
	power_shop_costs.clear()
	for power_name in power_shop_options:
		power_shop_costs[power_name] = get_power_cost(power_name)

func _on_no_pressed_local() -> void:
	request_cashout_no.rpc()

func _on_yes_pressed_local() -> void:
	request_cashout_yes.rpc()

@rpc("any_peer", "reliable")
func request_finish_powerup_selection() -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	var owner_index = connected_peers.find(sender_id)
	if owner_index == -1 or owner_index != cashout_owner_ind:
		return
	var shooter_peer_id = connected_peers[player_ind]
	if shooter_peer_id != -1:
		restore_ui_after_cashout.rpc_id(shooter_peer_id)
	end_round()

func get_power_cost(power_name: String) -> int:
	var base_cost = POWER_BASE_COSTS.get(power_name, 0)
	if base_cost == 0:
		return 0
	var variation = randi_range(-POWER_COST_VARIATION_PERCENT, POWER_COST_VARIATION_PERCENT)
	return int((base_cost * (100 + variation) + 50) / 100)

func get_local_player_index() -> int:
	return connected_peers.find(multiplayer.get_unique_id())

func get_local_player_money() -> int:
	var idx = get_local_player_index()
	if idx >= 0 and idx < money.size():
		return money[idx]
	return 0

func get_current_player_money() -> int:
	return money[player_ind]

func purchase_power(power_name: String, cost: int) -> bool:
	if cost <= 0:
		return false
	var local_index = get_local_player_index()
	if local_index == -1:
		return false
	if cost > money[local_index]:
		return false
	request_purchase_power.rpc(power_name, cost)
	return true

@rpc("authority", "call_local")
func purchase_result(success: bool) -> void:
	if success:
		update_powerup_shop()
	else:
		print("Purchase failed")

@rpc("any_peer", "reliable")
func request_purchase_power(power_name: String, cost: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	var buyer_index = connected_peers.find(sender_id)
	if buyer_index == -1:
		return

	if cost <= 0 or cost > money[buyer_index]:
		purchase_result.rpc_id(sender_id, false)
		return

	money[buyer_index] -= cost
	update_money_all.rpc(money)
	purchase_result.rpc_id(sender_id, true)


func update_powerup_shop() -> void:
	if not $pUI or not $pUI/Panel:
		return
	$pUI/Panel/MoneyLabel.text = "Money: %s" % get_local_player_money()
	var buttons = [
		$pUI/Panel/HBoxContainer/Power1,
		$pUI/Panel/HBoxContainer/Power2,
		$pUI/Panel/HBoxContainer/Power3
	]
	for i in range(buttons.size()):
		var button = buttons[i]
		if i < power_shop_options.size():
			var power_name = power_shop_options[i]
			var cost = power_shop_costs.get(power_name, 0)
			var used = power_shop_used.has(power_name)
			var affordable = cost > 0 and cost <= get_local_player_money()
			if used or not affordable:
				button.visible = false
				button.disabled = true
				button.set_meta("power_name", null)
				button.set_meta("power_cost", 0)
			else:
				button.visible = true
				button.disabled = false
				button.text = "%s (%d)" % [power_name.capitalize(), cost]
				button.set_meta("power_name", power_name)
				button.set_meta("power_cost", cost)
		else:
			button.visible = false
			button.disabled = true
			button.set_meta("power_name", null)
			button.set_meta("power_cost", 0)
	reroll_button.disabled = get_local_player_money() < 1
	var any_visible = false
	for button in buttons:
		if button.visible:
			any_visible = true
			break
	if not any_visible:
		if power_shop_used.size() >= power_shop_options.size():
			$pUI/Panel/NoticeLabel.text = "No power ups remain. Press Done."
		else:
			$pUI/Panel/NoticeLabel.text = "You lack funding. Play the game. Now."
		$pUI/Panel/NoticeLabel.visible = true
	else:
		$pUI/Panel/NoticeLabel.visible = false

@rpc("any_peer", "reliable")
func request_cashout_no() -> void:
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	if cashout_owner_ind == -1 or sender_id != connected_peers[cashout_owner_ind]:
		return

	money[cashout_owner_ind] += 3
	update_money_all.rpc(money)
	hide_cashout_menu.rpc_id(sender_id)
	restore_ui_after_cashout.rpc()
	cashout = false

	if play_again:
		play_again = false
		start_round()
	else:
		end_round()


@rpc("any_peer", "reliable")
func request_cashout_yes() -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if cashout_owner_ind == -1 or sender_id != connected_peers[cashout_owner_ind]:
		return
	cashout = false
	continue_after_crazy = true
	var owner_peer_id = connected_peers[cashout_owner_ind]
	$pUI/placementController.set_cashout_owner.rpc(owner_peer_id)
	start_crazy_mode.rpc_id(sender_id)
	game_state = GameState.CRAZY

@rpc("authority", "call_local")
func hide_cashout_menu() -> void:
	local_cashout_owner = false
	$CashOut.visible = false
	$UI.visible = true

@rpc("authority", "call_local")
func start_crazy_mode() -> void:
	local_cashout_owner = false
	$CashOut.visible = false
	$pUI.visible = true
	initialize_powerup_shop()
	update_powerup_shop()

@rpc("any_peer", "reliable")
func update_money_all(server_money: Array) -> void:
	money = server_money.duplicate()
