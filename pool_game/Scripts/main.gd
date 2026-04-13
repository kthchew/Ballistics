class_name Main extends Node3D

signal stopped_moving

@onready var debug_label: Label = $LabelLayer/DebugLabel
@onready var info_label: Label = $LabelLayer/InfoLabel
@onready var slider = $UI/SafeAreaContainer/ForceSlider
@onready var fire_button = $UI/SafeAreaContainer/FireButton
@onready var aimer = $UI/SafeAreaContainer/Aimer
@onready var menu_button = $UI/SafeAreaContainer/MenuButton
@onready var camera = $CameraPivot/Camera3D
@onready var hole_buttons = $UI/HoleButtons
@onready var aim_guide = $UI/AimVisuals/AimGuide
@onready var cue_stick = $UI/AimVisuals/CueStick
@onready var reroll_button: Button = $pUI/Panel/HBoxContainer2/RerollButton
@onready var shape_cast = $ShapeCast3D
@onready var ball_manager = $BallManager
@onready var classical_ai = $ClassicalAI

enum GameState {AIMING, MIDTURN, PLACING, PICKPOCKET, ENDED, CRAZY, NOT_STARTED, CASHOUT}
var cashout_owner_index: int = -1
var continue_after_crazy: bool = false
const POWER_BASE_COSTS := {"block": 5, "tungsten": 8, "tnt": 10}
const POWER_COST_VARIATION_PERCENT: int = 10
var shop_power_options: Array[String] = []
var shop_power_costs: Dictionary = {}
var used_shop_powers: Array[String] = []
const STATIC_TICKS_THRESHOLD: int = 60

var init_peer = null
var has_aimed := false
# physics defaults to 60 ticks per second
var cur_static_ticks = 0
var requesting_reset: Array[bool] = [false, false] # index is player index


@export var game_type: Utils.GameType = Utils.GameType.EIGHT_BALL_MULTIPLAYER
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

var persisted_game_id: String = ""
var persistence_enabled: bool = false
var persistence_usernames: Array[String] = ["", ""]
var persistence_tokens: Array[String] = ["", ""]
var persist_in_flight: bool = false

var about_to_exit = false

func _ready() -> void:
	if not OS.is_debug_build():
		debug_label.hide()
	
	$CashOut/Panel/VBoxContainer/HBoxContainer/Yes.pressed.connect(_on_yes_pressed_local)
	$CashOut/Panel/VBoxContainer/HBoxContainer/No.pressed.connect(_on_no_pressed_local)
	print("MAIN READY PATH:", get_path(), "\nGAME TYPE:", game_type)
	if init_peer != null:
		multiplayer.multiplayer_peer = init_peer
	
	aim_guide.hide()
	
	$UI/AimInputRegion.aim_changed.connect(_on_aim_input)
	slider.value_changed.connect(_on_force_changed.rpc)
	fire_button.pressed.connect(_on_fire_pressed)
	hole_buttons.hole_selected.connect(_on_hole_selected.rpc)
	
	if game_type == Utils.GameType.EIGHT_BALL_SINGLEPLAYER:
		classical_ai.ai_aimed.connect(_on_ai_aimed)
		classical_ai.ai_placed_cue_ball.connect(_on_ai_placed_cue_ball)
		classical_ai.ai_picked_pocket.connect(_on_ai_picked_pocket)
	
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
	
func _on_ai_aimed(dir: Vector2):
	aim(dir)
	
	slider.value = 50
	change_force(slider.value)
	
	await get_tree().create_timer(1.0).timeout
	
	fire_cue()
	
func _on_ai_placed_cue_ball(pos: Vector3):
	place_cue_ball(pos)
	
func _on_ai_picked_pocket(hole_ind: int):
	select_hole(hole_ind)

func aim(dir: Vector2):
	cast_aim_ray(dir.normalized())
	aim_guide.show()
	var other_peer = connected_peers[1 - player_ind]
	if Constants.AI_DRAW_AIM_GUIDE and game_type == Utils.GameType.EIGHT_BALL_SINGLEPLAYER and connected_peers[player_ind] == 1:
		cast_aim_ray.rpc_id(other_peer, dir.normalized())
		set_aim_guide_visibility.rpc_id(other_peer, true)
	
	aim_cue(dir)
	rpc_aim_cue.rpc_id(other_peer, dir)
	if not game_type == Utils.GameType.EIGHT_BALL_SINGLEPLAYER:
		rpc_aim_cue.rpc_id(1, dir)
	
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
	
func save() -> Dictionary:
	var ball_states: Array = []
	for ball in ball_manager.balls:
		ball_states.append(ball.save())

	var object_power_states: Array = []
	if has_node("pUI/placementController"):
		object_power_states = $pUI/placementController.save_object_powers()

	var current_username := ""
	var solids_username := ""
	var winner_username := ""
	if persistence_usernames.size() == 2:
		if player_ind >= 0 and player_ind < persistence_usernames.size():
			current_username = persistence_usernames[player_ind]
		if solids_player >= 0 and solids_player < persistence_usernames.size():
			solids_username = persistence_usernames[solids_player]
		if winner >= 0 and winner < persistence_usernames.size():
			winner_username = persistence_usernames[winner]

	var save_dict := {
		"current_player_index": player_ind,
		"current_player_username": current_username,
		"turn_num": turn_num,
		"round_num": round_num,
		"scores": scores.duplicate(),
		"balls_sunk": ball_manager.balls_sunk.duplicate(),
		"solids_player": solids_player,
		"solids_player_username": solids_username,
		"winner": winner,
		"winner_username": winner_username,
		"game_state": int(game_state),
		"player_usernames": persistence_usernames.duplicate(),
		"balls": ball_states,
		"object_powers": object_power_states,
		"play_again": play_again,
		
		"game_type": int(game_type),
		"continue_after_crazy": continue_after_crazy,
		"money": money.duplicate(),
		"power_shop_options": shop_power_options.duplicate(),
		"power_shop_costs": shop_power_costs.duplicate(),
		"power_shop_used": used_shop_powers.duplicate(),
	}
	return save_dict

func load(save_dict: Dictionary) -> void:
	set_visibility()
	set_visibility.rpc_id(connected_peers[0])
	set_visibility.rpc_id(connected_peers[1])
	
	has_aimed = false
	cue_stick.hide()
	slider.value = 0
	cue_stick.set_force_strength(0.0)
	aimer._reset_knob()

	player_ind = int(save_dict.get("current_player_index", 0))
	turn_num = int(save_dict.get("turn_num", 0))
	round_num = int(save_dict.get("round_num", 0))
	solids_player = int(save_dict.get("solids_player", -1))
	next_solids_player = int(save_dict.get("solids_player", -1))
	winner = int(save_dict.get("winner", -1))
	game_state = int(save_dict.get("game_state", GameState.AIMING)) as GameState
	play_again = bool(save_dict.get("play_again", false))
	continue_after_crazy = bool(save_dict.get("continue_after_crazy", false))
	
	game_type = int(save_dict.get("game_type", Utils.GameType.EIGHT_BALL_MULTIPLAYER)) as Utils.GameType
	money = save_dict.get("money", [0, 0])
	var opt_string_arr: Array[String]
	opt_string_arr.assign(save_dict.get("power_shop_options", []).duplicate())
	shop_power_options = opt_string_arr
	shop_power_costs = save_dict.get("power_shop_costs", {}).duplicate()
	var used_string_arr: Array[String]
	used_string_arr.assign(save_dict.get("power_shop_used", []).duplicate())
	used_shop_powers = used_string_arr
	
	if game_type == Utils.GameType.CRAZY_EIGHT_BALL_MULTIPLAYER:
		cashout_owner_index = 1 - player_ind
		set_cashout_owner.rpc(cashout_owner_index)
		$pUI/placementController.set_cashout_owner.rpc(connected_peers[cashout_owner_index])
		if game_state == GameState.CASHOUT:
			show_cashout_wait_menu.rpc(connected_peers[cashout_owner_index])
			show_cashout_menu.rpc_id(connected_peers[cashout_owner_index], cashout_owner_index)
		elif game_state == GameState.CRAZY:
			sync_power_shop_state(connected_peers[cashout_owner_index])
			show_crazy_mode_ui.rpc_id(connected_peers[cashout_owner_index])

	var saved_scores = save_dict.get("scores", [0, 0])
	if saved_scores is Array and saved_scores.size() == 2:
		scores = [int(saved_scores[0]), int(saved_scores[1])]

	var saved_sunk = save_dict.get("balls_sunk", [0, 0])
	if saved_sunk is Array and saved_sunk.size() == 2:
		var new_sunk: Array[int] = [int(saved_sunk[0]), int(saved_sunk[1])]
		ball_manager.balls_sunk = new_sunk

	var saved_usernames = save_dict.get("player_usernames", [])
	if saved_usernames is Array and saved_usernames.size() == 2:
		persistence_usernames = [str(saved_usernames[0]), str(saved_usernames[1])]

	# Prefer username references when available, then keep index fallback behavior.
	var current_username := str(save_dict.get("current_player_username", ""))
	if current_username != "" and persistence_usernames.size() == 2:
		var username_idx := persistence_usernames.find(current_username)
		if username_idx != -1:
			player_ind = username_idx

	var solids_username := str(save_dict.get("solids_player_username", ""))
	if solids_username != "" and persistence_usernames.size() == 2:
		var solids_idx := persistence_usernames.find(solids_username)
		if solids_idx != -1:
			solids_player = solids_idx

	var winner_username := str(save_dict.get("winner_username", ""))
	if winner_username != "" and persistence_usernames.size() == 2:
		var winner_idx := persistence_usernames.find(winner_username)
		if winner_idx != -1:
			winner = winner_idx

	var ball_lookup := {}
	for ball in ball_manager.balls:
		ball_lookup[ball.ball_num] = ball

	var saved_balls = save_dict.get("balls", [])
	if saved_balls is Array:
		for state in saved_balls:
			if not (state is Dictionary):
				continue
			var ball_num = int(state.get("ball_num", -1))
			if not ball_lookup.has(ball_num):
				continue
			var ball: Ball = ball_lookup[ball_num]
			var pos := Vector3(
				float(state.get("pos_x", ball.position.x)),
				float(state.get("pos_y", ball.position.y)),
				float(state.get("pos_z", ball.position.z))
			)
			ball.position = pos
			ball.teleport(pos)
			ball.rotation = Vector3(
				float(state.get("rot_x", ball.rotation.x)),
				float(state.get("rot_y", ball.rotation.y)),
				float(state.get("rot_z", ball.rotation.z))
			)
			ball.potted = bool(state.get("potted", false))
			if ball.potted:
				ball.freeze = true
				
			for modifier in state.get("modifiers", []):
				$pUI/placementController._apply_modifier(modifier, ball.get_path())
				$pUI/placementController.rpc_apply_modifier.rpc(modifier, ball.get_path())
			
			ball.show()

	if has_node("pUI/placementController"):
		var placement_controller = $pUI/placementController
		var saved_object_powers = save_dict.get("object_powers", [])
		if saved_object_powers is Array:
			placement_controller.load_object_powers(saved_object_powers)
		else:
			placement_controller.load_object_powers([])

	cur_static_ticks = 0

	if game_state == GameState.ENDED:
		ball_manager.freeze_balls()

func _get_persistence_token() -> String:
	for token in persistence_tokens:
		if token != "":
			return token
	return ""

func persist_game_state() -> void:
	if not multiplayer.is_server() or not persistence_enabled or persist_in_flight:
		return

	var backend = $/root/MultiplayerLobby/BackendRequests
	if backend == null:
		return

	persist_in_flight = true
	var state := save()

	if persisted_game_id == "":
		var created_game_id: String = await backend.create_new_game(state)
		if created_game_id != "":
			persisted_game_id = created_game_id
			# make game as joined for both players
			await backend.join_game(persistence_tokens[0], persisted_game_id)
			await backend.join_game(persistence_tokens[1], persisted_game_id)
	else:
		var ok: bool = await backend.set_game_state(state, persisted_game_id)
		if not ok:
			print("Failed to update game state for " + persisted_game_id)

	persist_in_flight = false

@rpc
func change_hole_button_visibility(visible_state: bool) -> void:
	hole_buttons.visible = visible_state
	
@rpc 
func set_hole_buttons_disabled(disabled_state: bool) -> void:
	for child in hole_buttons.get_children():
		if child is BaseButton:
			child.disabled = disabled_state
	
@rpc
func color_hole_button(hole_ind: int) -> void:
	var button = hole_buttons.get_node("HoleButton" + str(hole_ind + 1))
	var states = ["normal", "hover", "pressed", "disabled"]
	for state in states:
		var new_stylebox = button.get_theme_stylebox(state).duplicate()
		new_stylebox.bg_color = Color(0.2, 0.85, 0.4, 0.8)
		button.add_theme_stylebox_override(state, new_stylebox)

@rpc 
func reset_hole_button_color(hole_ind: int) -> void:
	var button = hole_buttons.get_node("HoleButton" + str(hole_ind + 1))
	hole_buttons.style_hole_button(button)

@rpc("any_peer", "reliable")
func _on_hole_selected(hole_ind: int) -> void:
	if not multiplayer.is_server() or connected_peers[player_ind] != multiplayer.get_remote_sender_id() or game_state != GameState.PICKPOCKET:
		return
	select_hole(hole_ind)

func select_hole(hole_ind: int) -> void:
	target_hole = hole_ind
	
	set_hole_buttons_disabled.rpc_id(connected_peers[player_ind], true)
	set_hole_buttons_disabled.rpc_id(connected_peers[1 - player_ind], true)
	color_hole_button.rpc_id(connected_peers[player_ind], hole_ind)
	color_hole_button.rpc_id(connected_peers[1 - player_ind], hole_ind)
	
	await get_tree().create_timer(1.0).timeout
	
	change_hole_button_visibility.rpc_id(connected_peers[player_ind], false)
	change_hole_button_visibility.rpc_id(connected_peers[1 - player_ind], false)
	reset_hole_button_color.rpc_id(connected_peers[player_ind], hole_ind)
	reset_hole_button_color.rpc_id(connected_peers[1 - player_ind], hole_ind)
	
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
	
	if game_type == Utils.GameType.EIGHT_BALL_SINGLEPLAYER:
		requesting_reset = [true, true]
	else:
		requesting_reset[changer_ind] = not requesting_reset[changer_ind]
	var request_label = $UI/PauseMenu/GridContainer/ResetInfo/ResetRequestedLabel
	request_label.visible = requesting_reset[changer_ind]
	
	if requesting_reset[this_ind]:
		request_label.text = "You have requested a reset."
	else:
		request_label.text = "Your opponent requests a reset."
		if request_label.visible:
			menu_button.start_pulsing()
	
	if requesting_reset[0] and requesting_reset[1]:
		if multiplayer.is_server():
			start_game()
		request_label.visible = false
		requesting_reset = [false, false]
	
	if not request_label.visible:
		menu_button.stop_pulsing()

func _on_first_hit_ball_changed():
	ball_manager.check_cue_ball_first_hit(player_ind, solids_player, scores)
	
func _on_ball_sunk(ball):
	if not multiplayer.is_server():
		return
	if ball.is_eight_ball():
		var hole_ind = Shot.calc_hole_ind_from_pos(ball.position)
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

func shapecast_point_to_point(origin: Vector3, rel_target: Vector3) -> bool:
	shape_cast.global_position = origin
	shape_cast.max_results = 1
	shape_cast.target_position = rel_target
	shape_cast.collision_mask = 1 << 2
	shape_cast.force_shapecast_update()
	return not shape_cast.is_colliding()

@rpc("any_peer")
func set_aim_guide_visibility(visible: bool):
	aim_guide.visible = visible

@rpc("any_peer")
func cast_aim_ray(aim_dir: Vector2) -> void:
	var origin = ball_manager.get_cue_ball_global_pos()
	var dir = Vector3(aim_dir.x, 0, aim_dir.y).normalized()
	if shapecast_point_to_point(origin, 500 * dir):
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
	
	aim_guide.hide()
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
	active_power_objects = 0
	
	reset_local_state.rpc()
	
	requesting_reset = [false, false]
	
	ball_manager.start_game()
	start_round()
	
@rpc("call_local")
func reset_local_state():
	aim_guide.hide()
	
	$pUI/placementController.remove_all_placed_powers()
	ball_manager.clear_crazy_modifiers()
			
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
		if shapecast_point_to_point(intersection, Vector3.ZERO) \
			and abs(intersection.x) < 96 \
			and abs(intersection.z) < 44.5:
			_on_place_cue_ball.rpc_id(1, intersection)
	elif game_state == GameState.AIMING:
		if ball_manager.check_cue_ball_potted_by_pos():
			return
		# calculate difference between cue ball position and touch pos, use that to set cue stick angle
		# this is done so that the vector provided to the server is consistent even if the window's size or aspect ratio is different
		var ball_center_3d = ball_manager.get_cue_ball_global_pos()
		var ball_screen_pos: Vector2 = camera.unproject_position(ball_center_3d)
		var dir: Vector2 = ball_screen_pos - touch_pos
		if dir.length() >= 20:
			aim(dir)

@rpc("any_peer")
func _on_place_cue_ball(place_global_pos: Vector3):
	if not multiplayer.is_server() or connected_peers[player_ind] != multiplayer.get_remote_sender_id() or game_state != GameState.PLACING:
		return
	place_cue_ball(place_global_pos)

func place_cue_ball(place_global_pos: Vector3):
	ball_manager.reset_cue_ball(place_global_pos)
	start_round()

@rpc("any_peer", "reliable")
func rpc_aim_cue(dir_from_cue: Vector2):
	if multiplayer.get_remote_sender_id() != 0 and connected_peers[player_ind] != multiplayer.get_remote_sender_id():
		return
	aim_cue(dir_from_cue)

func aim_cue(dir_from_cue: Vector2):
	has_aimed = true

	var ball_center_3d = ball_manager.get_cue_ball_global_pos()
	var angle: float = dir_from_cue.angle()

	cue_stick.update_position(ball_center_3d)
	cue_stick.set_angle(angle)
	cue_stick.show()

@rpc("any_peer", "reliable")
func _on_force_changed(value: float):
	if not multiplayer.is_server() or connected_peers[player_ind] != multiplayer.get_remote_sender_id():
		return
	change_force(value)
		
func change_force(value: float):
	var normalized = value / $UI/SafeAreaContainer/ForceSlider.max_value
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
	rpc_fire_cue.rpc_id(1)
	aim_guide.hide()
	
	has_aimed = false
	slider.value = 0
	cue_stick.set_force_strength(0.0)
	aimer._reset_knob()

@rpc("any_peer", "reliable")
func rpc_fire_cue():
	if not multiplayer.is_server() or connected_peers[player_ind] != multiplayer.get_remote_sender_id():
		return
	fire_cue()
	
func fire_cue():
	if game_state != GameState.AIMING or not has_aimed:
		return
	if Constants.AI_DRAW_AIM_GUIDE and game_type == Utils.GameType.EIGHT_BALL_SINGLEPLAYER:
		set_aim_guide_visibility.rpc_id(connected_peers[1 - player_ind], false)
		classical_ai.circle_artist.clear_all()
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
	persist_game_state()
		
func is_ai_turn():
	return game_type == Utils.GameType.EIGHT_BALL_SINGLEPLAYER and connected_peers[player_ind] == 1
	
func ai_play():
	await get_tree().create_timer(1.0).timeout
	
	classical_ai.find_shot(
		ball_manager.cue_ball,
		ball_manager.get_pottable_balls(player_ind, solids_player, scores)
	)
	
	if game_state == GameState.PLACING:
		classical_ai.place_cue_ball()
	elif game_state == GameState.PICKPOCKET:
		classical_ai.pick_pocket()
	elif game_state == GameState.AIMING:
		classical_ai.shoot()
		
func start_round(scratched_prev: bool = false) -> void:
	if scratched_prev:
		if ball_manager.check_eight_ball_potted():
			end_game(player_ind)
		print("Scratch registered")
		game_state = GameState.PLACING
		ball_manager.cue_ball.pot()
	elif target_hole == -1 and scores[player_ind] >= Constants.BALLS_BEFORE_EIGHT:
		game_state = GameState.PICKPOCKET
		change_hole_button_visibility.rpc_id(connected_peers[player_ind], true)
		change_hole_button_visibility.rpc_id(connected_peers[1 - player_ind], true)
		set_hole_buttons_disabled.rpc_id(connected_peers[player_ind], false)
		set_hole_buttons_disabled.rpc_id(connected_peers[1 - player_ind], true)
	else:
		game_state = GameState.AIMING
	
	if is_ai_turn():
		ai_play()
	
func update_cashout_label() -> void:
	var owner_money_text = "Money: ?"
	var owner_index = cashout_owner_index
	if owner_index == -1:
		owner_index = get_local_player_index()
	if owner_index >= 0 and owner_index < money.size():
		owner_money_text = "Money: " + str(money[owner_index])
	$CashOut/Panel/VBoxContainer/Label.text = "Cashout decision\n" + owner_money_text + "\nDo you want to cash out?"

@rpc("authority", "reliable")
func show_cashout_wait_menu(owner_peer_id: int) -> void:
	if multiplayer.get_unique_id() == owner_peer_id:
		return
	game_state = GameState.CASHOUT
	$UI.visible = false

@rpc("authority", "reliable")
func restore_ui_after_cashout() -> void:
	$UI.visible = true

@rpc("authority", "reliable")
func set_cashout_owner(owner_index: int) -> void:
	cashout_owner_index = owner_index

@rpc("authority", "reliable")
func show_cashout_menu(owner_index: int) -> void:
	cashout_owner_index = owner_index
	game_state = GameState.CASHOUT
	$UI.visible = false
	$CashOut.visible = true
	update_cashout_label()
	$pUI.visible = false
	
func end_round() -> void:
	if game_type == Utils.GameType.EIGHT_BALL_SINGLEPLAYER:
		classical_ai.reset_shot()
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
			cashout_owner_index = 1 - player_ind
			set_cashout_owner.rpc(cashout_owner_index)
			var cashout_peer_id = connected_peers[cashout_owner_index]
			if cashout_peer_id != -1:
				game_state = GameState.CASHOUT
				show_cashout_wait_menu.rpc(cashout_peer_id)
				if cashout_peer_id == multiplayer.get_unique_id():
					show_cashout_menu(cashout_owner_index)
				else:
					show_cashout_menu.rpc_id(cashout_peer_id, cashout_owner_index)
			await persist_game_state()
			return
		else:
			play_again = false
			start_round(scratched)
			await persist_game_state()
			stopped_moving.emit()
			return
	
	play_again = false
	turn_num += 1
	player_ind = 1 - player_ind
	start_round(scratched)
	await persist_game_state()
	stopped_moving.emit()
	
func process_midturn():
	# cue_stick.visible = false
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
	if not multiplayer.is_server() or game_state != GameState.MIDTURN:
		return
	process_midturn()

func _process(delta: float) -> void:
	if OS.is_debug_build():
		fill_debug_label()
	fill_info_label()
	if $pUI and $pUI.visible:
		update_powerup_shop()

func is_your_turn() -> bool:
	if connected_peers and connected_peers.size() > player_ind:
		return connected_peers[player_ind] == multiplayer.get_unique_id() or 1 == multiplayer.get_unique_id()
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
	if cashout_owner_index < 0 or cashout_owner_index >= connected_peers.size():
		return -1
	return connected_peers[cashout_owner_index]

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
	if game_state == GameState.CRAZY:
		if is_local_cashout_owner():
			info_label.text += "Buy and use powerups in the shop.\n"
		else:
			info_label.text += "Opponent is deciding which powerups to use before your next move.\n"
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
			
	if about_to_exit:
		info_label.text += "The other player left the game - returning to menu in a few seconds..."

var active_power_objects: int = 0

func _on_done_powerup_pressed() -> void:
	$pUI.visible = false
	$UI.visible = true
	request_finish_powerup_selection.rpc()

func _on_reroll_powerup_pressed() -> void:
	request_reroll_power_shop.rpc()

func refresh_power_shop_inventory(clear_used: bool = false) -> void:
	if not multiplayer.is_server():
		return
	if active_power_objects > 0:
		shop_power_options = ["block", "tungsten", "tnt"]
	else:
		shop_power_options = ["block", "tungsten"]
	shop_power_options.shuffle()
	if clear_used:
		used_shop_powers.clear()
	shop_power_costs.clear()
	for power_name in shop_power_options:
		shop_power_costs[power_name] = roll_power_cost(power_name)

func sync_power_shop_state(target_peer_id: int = -1) -> void:
	if not multiplayer.is_server():
		return
	if target_peer_id == -1:
		apply_power_shop_state.rpc(shop_power_options, shop_power_costs, used_shop_powers)
	else:
		apply_power_shop_state.rpc_id(target_peer_id, shop_power_options, shop_power_costs, used_shop_powers)

@rpc("authority", "reliable", "call_local")
func apply_power_shop_state(options: Array, costs: Dictionary, used: Array) -> void:
	var options_cast: Array[String]
	options_cast.assign(options)
	shop_power_options = options_cast
	shop_power_costs = costs.duplicate()
	var used_cast: Array[String]
	used_cast.assign(used)
	used_shop_powers = used_cast
	update_powerup_shop()

func _on_no_pressed_local() -> void:
	request_cashout_no.rpc()

func _on_yes_pressed_local() -> void:
	request_cashout_yes.rpc()

@rpc("any_peer", "reliable")
func request_reroll_power_shop() -> void:
	if not multiplayer.is_server() or game_state != GameState.CRAZY:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if cashout_owner_index == -1 or sender_id != connected_peers[cashout_owner_index]:
		return
	var owner_index = connected_peers.find(sender_id)
	if owner_index == -1 or money[owner_index] < 1:
		return
	money[owner_index] -= 1
	refresh_power_shop_inventory(true)
	sync_power_shop_state(sender_id)
	await persist_game_state()

@rpc("any_peer", "reliable")
func request_finish_powerup_selection() -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	var owner_index = connected_peers.find(sender_id)
	if owner_index == -1 or owner_index != cashout_owner_index:
		return
	var shooter_peer_id = connected_peers[player_ind]
	if shooter_peer_id != -1:
		restore_ui_after_cashout.rpc_id(shooter_peer_id)
	end_round()

func roll_power_cost(power_name: String) -> int:
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

func server_try_consume_power_purchase(sender_id: int, power_name: String) -> bool:
	if not multiplayer.is_server() or game_state != GameState.CRAZY:
		return false
	if cashout_owner_index == -1 or sender_id != connected_peers[cashout_owner_index]:
		return false
	if not shop_power_options.has(power_name) or used_shop_powers.has(power_name):
		return false
	var owner_index = connected_peers.find(sender_id)
	if owner_index == -1:
		return false
	var cost = int(shop_power_costs.get(power_name, 0))
	if cost <= 0 or cost > money[owner_index]:
		return false
	money[owner_index] -= cost
	used_shop_powers.append(power_name)
	sync_power_shop_state(sender_id)
	return true

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
		if i < shop_power_options.size():
			var power_name = shop_power_options[i]
			var cost = shop_power_costs.get(power_name, 0)
			var used = used_shop_powers.has(power_name)
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
		if used_shop_powers.size() >= shop_power_options.size():
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
	if cashout_owner_index == -1 or sender_id != connected_peers[cashout_owner_index]:
		return

	money[cashout_owner_index] += 3
	hide_cashout_menu.rpc_id(sender_id)
	restore_ui_after_cashout.rpc()
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
	if cashout_owner_index == -1 or sender_id != connected_peers[cashout_owner_index]:
		return
	continue_after_crazy = true
	var owner_peer_id = connected_peers[cashout_owner_index]
	refresh_power_shop_inventory(true)
	sync_power_shop_state(sender_id)
	$pUI/placementController.set_cashout_owner.rpc(owner_peer_id)
	show_crazy_mode_ui.rpc_id(sender_id)
	game_state = GameState.CRAZY

@rpc("authority", "call_local")
func hide_cashout_menu() -> void:
	$CashOut.visible = false
	$UI.visible = true

@rpc("authority", "call_local")
func show_crazy_mode_ui() -> void:
	$CashOut.visible = false
	$pUI.visible = true
	update_powerup_shop()


func _on_menu_button_pressed() -> void:
	$UI/PauseMenu.show()
	menu_button.stop_pulsing()

func _on_menu_resume_button_pressed() -> void:
	$UI/PauseMenu.hide()

func _on_menu_exit_button_pressed() -> void:
	ball_manager.stop_synchronizing_all_balls()
	get_tree().get_root().multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().call_deferred("change_scene_to_file", "res://Scenes/Menu.tscn")
	
func _new_delta_sync_received() -> void:
	# delta sync can be a change in money
	update_cashout_label()
	update_powerup_shop()
