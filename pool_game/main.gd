extends Node3D


@onready var debug_label: Label = $UI/DebugLabel
@onready var info_label: Label = $UI/InfoLabel
@onready var aim_line = $UI/AimLine
@onready var slider = $UI/ForceSlider
@onready var fire_button = $UI/FireButton
@onready var aimer = $UI/Aimer
@onready var camera = $CameraPivot/Camera3D

enum GameState {AIMING, MIDTURN, PLACING, ENDED}
const STATIC_TICKS_THRESHOLD: int = 60
const SPEED_THRESH: float = 0.25
const ANGULAR_SPEED_THRESH: float = 0.25
const BALL_COLORS = [
	[255, 215, 4], 
	[0, 0, 254], 
	[255, 0, 0], 
	[128, 0, 129], 
	[254, 165, 0], 
	[35, 139, 35], 
	[128, 0, 1],
	[0, 0, 0],
]

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

const ball_scene = preload("res://ball.tscn")	
const ball_script = preload("res://ball.gd")	

func _ready() -> void:
	
	create_balls()
	start_game()
	
	$UI/AimInputRegion.aim_changed.connect(_on_aim_changed)
	slider.value_changed.connect(_on_force_changed)
	fire_button.pressed.connect(_on_fire_pressed)
	
func create_balls() -> void:
	balls = []
	ball_scene.instantiate()
	for i in range(16):
		var ball: RigidBody3D = ball_scene.instantiate()
		add_child(ball)
		ball.ball_num = i
		ball.name = "Ball%s" % i
		balls.append(ball)
		if i == 0:
			cue_ball = ball
			cue_ball.body_entered.connect(cue_ball._on_body_entered)
			cue_ball.contact_monitor = true
			cue_ball.max_contacts_reported = 3
		else:
			color_ball(ball)
	
func start_game() -> void:
	
	cue_ball.reset(Vector3(-56.0, ball_script.BALL_RADIUS, 0))
	place_rack(56, 0)
	
	has_aimed = false
	aim_line.visible = false
	game_state = GameState.AIMING
	
	player_ind = 0
	cur_static_ticks = 0
	solids_player = -1
	next_solids_player = -1
	scores = [0, 0]
	balls_sunk = [0, 0]
	turn_num = 0
	play_again = false
	
func color_ball(ball_node: RigidBody3D) -> void:
	var mesh = ball_node.get_node("MeshInstance3D")
	var material: Material = StandardMaterial3D.new()
	
	var color_num = ball_node.ball_num
	
	if color_num > 8:
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
	
	if color_num > 8:
		color_num -= 8
	var color = BALL_COLORS[color_num - 1]
	material.albedo_color = Color(color[0] / 255.0, color[1] / 255.0, color[2] / 255.0)
	
	mesh.set_surface_override_material(0, material)
			
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
			balls[ball_ind].rotation = Vector3(0, 0, PI / 2)
			
			ball_ind += 1
	
	balls[2].teleport(Vector3(0, 0, 35))
	balls[1].teleport(Vector3(0, 0, 40))
	

func _on_aim_changed(touch_pos: Vector2):
	if game_state == GameState.MIDTURN or game_state == GameState.ENDED:
		return
		
	if game_state == GameState.PLACING:
		var ray_origin = camera.project_ray_origin(touch_pos)
		var ray_normal = camera.project_ray_normal(touch_pos)
		var drop_plane = Plane(Vector3.UP, Vector3(0, ball_script.BALL_RADIUS, 0))
		var intersection = drop_plane.intersects_ray(ray_origin, ray_normal)
		cue_ball.reset(intersection)
		game_state = GameState.AIMING
		has_aimed = false
		return
		
	var ball_screen_pos: Vector2 = camera.unproject_position(cue_ball.global_position)
	var dir = touch_pos - ball_screen_pos

	if dir.length() < 20:
		return

	if not has_aimed:
		has_aimed = true
		aim_line.visible = true
		
	aim_line.global_position = ball_screen_pos
	aim_line.set_angle(dir.angle())

func _on_force_changed(value):
	var normalized = value / $UI/ForceSlider.max_value
	$UI/AimLine.set_force_strength(normalized)

func _on_fire_pressed():
	var strength = slider.value
	var angle = aim_line.angle

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

	var local_offset = offset_3d

	cue_ball.apply_impulse(force, local_offset)
	cue_ball.first_hit_ball_num = 0
	
	game_state = GameState.MIDTURN

	has_aimed = false
	aim_line.visible = false
	aimer._reset_knob()
	
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
	
func process_fallen_ball(ball: RigidBody3D) -> void:
	if ball.is_eight_ball():
		if scores[player_ind] == 7:
			scores[player_ind] += 1
			end_game(player_ind)
		else:
			scores[player_ind] = -1000
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
	if scores[player_ind] == 7 and first_hit_ball_num == 8:
		return false
	if solids_player == player_ind and not (1 <= first_hit_ball_num and first_hit_ball_num <= 7):
		return true
	if solids_player == 1 - player_ind and not (9 <= first_hit_ball_num and first_hit_ball_num <= 15):
		return true
	return false
	
func check_for_scratch():
	return cue_ball.potted or check_for_first_hit_scratch()

func start_new_turn() -> void:
	if check_for_scratch():
		print("Scratch registered")
		cue_ball.pot()
		game_state = GameState.PLACING
		player_ind = 1 - player_ind
	else:
		game_state = GameState.AIMING
		if not play_again:
			player_ind = 1 - player_ind
	
	print("Starting new turn")
	cue_ball.first_hit_ball_num = -1
	turn_num += 1
	play_again = false
	if next_solids_player != -1:
		solids_player = next_solids_player
	
func _physics_process(delta: float) -> void:
	if game_state != GameState.MIDTURN:
		return
		
	process_fallen_balls()
	
	if check_all_not_moving():
		cur_static_ticks += 1
	else:
		cur_static_ticks = 0
	
	if cur_static_ticks == STATIC_TICKS_THRESHOLD:
		start_new_turn()
	
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
	
	if game_state == GameState.PLACING or game_state == GameState.AIMING:
		info_label.text += "Player " + str(player_ind + 1) + "'s turn.\n"
		if player_ind == solids_player:
			info_label.text += "You are solids\n"
		elif 1 - player_ind == solids_player:
			info_label.text += "You are stripes\n"
			
	if game_state == GameState.PLACING:
		info_label.text += "Your opponent scratched, click to place the cue ball\n"

func _process(delta: float) -> void:
	fill_debug_label()
	fill_info_label()

func _on_reset_button_pressed() -> void:
	start_game()
