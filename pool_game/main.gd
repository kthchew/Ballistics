extends Node3D


@onready var debug_label: Label = $UI/DebugLabel
@onready var info_label: Label = $UI/InfoLabel
@onready var slider = $UI/ForceSlider
@onready var fire_button = $UI/FireButton
@onready var aimer = $UI/Aimer
@onready var camera = $CameraPivot/Camera3D
@onready var hole_buttons = $UI/HoleButtons
@onready var cue_stick = $CueStick

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
@export var player_ind: int = 0
@export var scores: Array[int] = [0, 0]
@export var balls_sunk: Array[int] = [0, 0]
@export var game_state: GameState = GameState.AIMING
@export var turn_num: int = 0
@export var solids_player = -1
@export var next_solids_player = -1
@export var winner: int = -1
@export var play_again: bool = false
@export var target_hole: int = -1
var connected_peers = [-1, -1] # index is player index, value is peer id

const ball_scene = preload("res://ball.tscn")	
const ball_script = preload("res://ball.gd")	

func _ready() -> void:
	create_balls()
	place_rack(56, 0)
	hole_buttons.hide()
	
	cue_stick.visible = false
	$OverheadLight/Light.light_energy = 1000
	
	$UI/AimInputRegion.aim_changed.connect(_on_aim_changed.rpc)
	slider.value_changed.connect(_on_force_changed.rpc)
	fire_button.pressed.connect(_on_fire_pressed.rpc)
	hole_buttons.hole_selected.connect(_on_hole_selected)
	
	var args := OS.get_cmdline_args()
	for a in args:
		if a == "--server":
			start_server(7777)
		elif a.begins_with("--connect="):
			var host = a.get_slice("=", 1)
			start_client(host, 7777)
		else:
			start_client("127.0.0.1", 7777)
	
func _on_hole_selected(hole_ind: int) -> void:
	target_hole = hole_ind
	hole_buttons.hide()
	start_round()
	
func create_balls() -> void:
	balls = []
	ball_scene.instantiate()
	for i in range(16):
		var ball: RigidBody3D = ball_scene.instantiate()
		ball.ball_num = i
		ball.name = "Ball%s" % i
		start_synchronizing_ball.rpc(ball.get_name())
		add_child(ball)
		balls.append(ball)
		rpc_color_ball.rpc(ball.get_name())
		if i == 0:
			cue_ball = ball
			cue_ball.body_entered.connect(cue_ball._on_body_entered)
			cue_ball.contact_monitor = true
			cue_ball.max_contacts_reported = 3
	
func start_game() -> void:
	
	cue_ball.reset(Vector3(-56.0, ball_script.BALL_RADIUS, 0))
	
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
	
	place_rack(56, 0)
	
@rpc("authority", "call_local", "reliable")
func rpc_color_ball(ball_name: String) -> void:
	var ball_node = get_node(ball_name)
	color_ball(ball_node)
	
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
			
func start_server(port: int = 7777) -> void:
	print("Starting server on port %d" % port)
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(port, 4)
	get_tree().get_root().multiplayer.multiplayer_peer = peer
	get_tree().get_root().multiplayer.connect("peer_connected", Callable(self, "_on_peer_connected"))
	get_tree().get_root().multiplayer.connect("peer_disconnected", Callable(self, "_on_peer_disconnected"))
	get_tree().get_root().multiplayer.connect("server_disconnected", Callable(self, "_on_server_disconnected"))

func start_client(host: String, port: int = 7777) -> void:
	print("Connecting to server %s:%d" % [host, port])
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(host, port)
	get_tree().get_root().multiplayer.multiplayer_peer = peer
	get_tree().get_root().multiplayer.connect("connected_to_server", Callable(self, "_on_connected_to_server"))
	get_tree().get_root().multiplayer.connect("connection_failed", Callable(self, "_on_connection_failed"))
	get_tree().get_root().multiplayer.connect("server_disconnected", Callable(self, "_on_server_disconnected"))
	
func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("Peer connected: %d" % id)
	if connected_peers[0] == -1:
		connected_peers[0] = id
	elif connected_peers[1] == -1:
		connected_peers[1] = id
		start_game()
	else:
		print("Peer connected but no space in room")

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("Peer disconnected: %d" % id)

func _on_connected_to_server() -> void:
	print("Connected to server")

func _on_connection_failed() -> void:
	print("Connection failed")

func _on_server_disconnected() -> void:
	print("Disconnected from server")

@rpc("any_peer", "reliable")
func _on_aim_changed(touch_pos: Vector2):
	if not multiplayer.is_server() or connected_peers[player_ind] != multiplayer.get_remote_sender_id():
		return
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
	
@rpc("any_peer", "reliable")
func _on_fire_pressed():
	if not multiplayer.is_server() or connected_peers[player_ind] != multiplayer.get_remote_sender_id():
		return
	var strength = cue_stick.strength * 100
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
		cue_stick.visible = false
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
	
@rpc("authority", "call_local", "reliable")
func start_synchronizing_ball(ball_name: String):
	var rep_config = $MultiplayerSynchronizer.get_replication_config()
	rep_config.add_property(ball_name + ":position")
	rep_config.add_property(ball_name + ":rotation")
	rep_config.add_property(ball_name + ":angular_velocity")
	rep_config.add_property(ball_name + ":linear_velocity")
	rep_config.add_property(ball_name + ":ball_num")
	$MultiplayerSynchronizer.set_replication_config(rep_config)
	
@rpc("authority", "call_local", "reliable")
func stop_synchronizing_ball(ball_name: String):
	var rep_config = $MultiplayerSynchronizer.get_replication_config()
	rep_config.remove_property(ball_name + ":position")
	rep_config.remove_property(ball_name + ":rotation")
	rep_config.remove_property(ball_name + ":angular_velocity")
	rep_config.remove_property(ball_name + ":linear_velocity")
	rep_config.add_property(ball_name + ":ball_num")
	$MultiplayerSynchronizer.set_replication_config(rep_config)
	
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
	
	target_hole = -1
	if next_solids_player != -1:
		solids_player = next_solids_player
	
	var scratched = check_for_scratch()
	cue_ball.first_hit_ball_num = -1
	
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
	
func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		if game_state != GameState.MIDTURN:
			return
		elif game_state == GameState.MIDTURN:
			cue_stick.visible = false
			
		process_fallen_balls()
		
		if check_all_not_moving():
			cur_static_ticks += 1
		else:
			cur_static_ticks = 0
		
		if cur_static_ticks == STATIC_TICKS_THRESHOLD:
			end_round()
	
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

func _process(delta: float) -> void:
	fill_debug_label()
	fill_info_label()

func _on_reset_button_pressed() -> void:
	start_game()
