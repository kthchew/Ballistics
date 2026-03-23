extends Node

signal ball_sunk(ball: RigidBody3D)

const SPEED_THRESH: float = 0.25
const ANGULAR_SPEED_THRESH: float = 0.25
# sometimes we change the below constant for playtesting
const ball_scene = preload("res://ball.tscn")

var balls: Array[Ball]
var balls_sunk: Array[int] = [0, 0]
var cue_ball: Ball
var first_hit_scratch: bool

func init():
	create_balls()
	
func start_game():
	cue_ball.reset(Vector3(-56, Constants.BALL_RADIUS, 0))
	place_rack(56, 0)
	remove_material_overlays()
	
	#pot_unused_balls()
	#setup_two_ball_shot()
	#setup_scratch()
	balls_sunk = [0, 0]
	
func end_round():
	first_hit_scratch = false
	cue_ball.first_hit_ball_num = -1
	remove_material_overlays()
	
func get_cue_ball_global_pos():
	return cue_ball.global_position
	
func hit_cue_ball(force: Vector3, offset_3d: Vector3):
	cue_ball.apply_impulse(force, offset_3d)
	cue_ball.first_hit_ball_num = 0
	
func reset_cue_ball(pos: Vector3):
	cue_ball.reset(pos)
	
func freeze_balls():
	for ball in balls:
		ball.freeze = true
		
func check_scratch():
	return cue_ball.potted or first_hit_scratch
	
func check_eight_ball_potted():
	return balls[5].potted
	
func check_cue_ball_potted_by_pos():
	return cue_ball.position.z > 60
	
func check_cue_ball_first_hit(player_ind: int, solids_player: int, scores: Array[int]) -> void:
	first_hit_scratch = not check_is_ball_valid(cue_ball.first_hit_ball_num, player_ind, solids_player, scores)

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
			ball.collision_layer += Constants.SHAPECAST_LAYER

func place_rack(x_shift: float, z_shift: float, spacing: float = 1.05):
	balls.sort_custom(func(a, b): return a.ball_num < b.ball_num)
	var ball_perm = range(16)
	ball_perm.erase(0)
	ball_perm.erase(8)
	ball_perm.shuffle()
	ball_perm.insert(0, 0)
	ball_perm.insert(5, 8)
	
	var new_balls: Array[Ball] = []
	for i in range(16):
		new_balls.append(balls[ball_perm[i]])
	balls = new_balls
	
	var ball_ind: int = 1
	for i in range(5):
		for j in range(i + 1):
			var x: float = x_shift + spacing * i * Constants.BALL_RADIUS * sqrt(3)
			var z: float = z_shift + (-i + 2 * j) * Constants.BALL_RADIUS * spacing
			balls[ball_ind].reset(Vector3(x, Constants.BALL_RADIUS, z))
			balls[ball_ind].rotation = Vector3(PI / 2, 0, PI)
			
			ball_ind += 1
			
func color_ball(ball_node: RigidBody3D) -> void:
	var texture_path = "res://ball_textures/Ball" + str(ball_node.ball_num) + ".jpg"
	var ball_texture = load(texture_path)
	
	var material: Material = StandardMaterial3D.new()
	material.albedo_texture = ball_texture
	material.roughness = 0.3
	
	var mesh = ball_node.get_node("MeshInstance3D")
	mesh.set_surface_override_material(0, material)
	
func remove_material_overlays():
	for ball in balls:
		var mesh = ball.get_node("MeshInstance3D")
		mesh.material_overlay = null
	
func check_all_not_moving() -> bool:
	for ball in balls:
		if ball.get_linear_velocity().length() > SPEED_THRESH \
		or ball.get_angular_velocity().length() > ANGULAR_SPEED_THRESH:
			return false
	return true
	
func pot_unused_balls():
	for ball in balls:
		if ball.ball_num in range(1, 1 + (7 - Constants.BALLS_BEFORE_EIGHT)):
			process_fallen_ball(ball)
		if ball.ball_num in range (9, 9 + (7 - Constants.BALLS_BEFORE_EIGHT)):
			process_fallen_ball(ball)
			
func setup_two_ball_shot():
	for ball in balls:
		if ball.is_cue_ball():
			ball.teleport(Vector3(0, Constants.BALL_RADIUS, 40))
		elif ball.is_eight_ball():
			ball.teleport(Vector3(0, Constants.BALL_RADIUS, 0))
		elif ball.ball_num == 1:
			ball.teleport(Vector3(0, Constants.BALL_RADIUS, -30))
		elif ball.ball_num == 2:
			ball.teleport(Vector3(20, Constants.BALL_RADIUS, 0))
		else:
			ball.pot()
			
func setup_scratch():
	for ball in balls:
		if ball.is_eight_ball():
			ball.teleport(Vector3(0, Constants.BALL_RADIUS, 0))
		elif ball.ball_num == 1:
			ball.teleport(Vector3(0, Constants.BALL_RADIUS, -30))
		elif ball.ball_num == 2:
			ball.teleport(Vector3(20, Constants.BALL_RADIUS, -5))
		else:
			ball.pot()
	
	
func find_fallen_balls() -> Array[RigidBody3D]:
	var fallen_balls: Array[RigidBody3D] = []
	for ball in balls:
		if ball.position.y < -10:
			fallen_balls.append(ball)
	return fallen_balls

func process_fallen_balls() -> void:
	var fallen_balls: Array[RigidBody3D] = find_fallen_balls()
	for ball in fallen_balls:
		process_fallen_ball(ball)

func process_fallen_ball(ball: RigidBody3D) -> void:
	print(ball.name + " fell")
	if ball.is_solid():
		balls_sunk[0] += 1
	elif ball.is_stripe():
		balls_sunk[1] += 1
	ball_sunk.emit(ball)
	ball.pot()
	
# valid meaning allowed to hit the ball first and it's not a scratch
func check_is_ball_valid(ball_num: int, player_ind: int, solids_player: int, scores: Array[int]) -> bool:
	if ball_num == 0:
		return false
	if solids_player == -1:
		return ball_num != 8
	if scores[player_ind] >= Constants.BALLS_BEFORE_EIGHT:
		return ball_num == 8
	if player_ind == solids_player:
		return 1 <= ball_num and ball_num <= 7
	else:
		return 9 <= ball_num and ball_num <= 15
		
func get_pottable_balls(player_ind: int, solids_player: int, scores: Array[int]):
	var ans: Array[Ball] = []
	for ball in balls:
		if ball.potted:
			continue
		if check_is_ball_valid(ball.ball_num, player_ind, solids_player, scores):
			ans.append(ball)
	return ans
