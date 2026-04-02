extends Node

signal ball_sunk(ball: RigidBody3D)


const SPEED_THRESH: float = 0.25
const ANGULAR_SPEED_THRESH: float = 0.25
# sometimes we change the below constant for playtesting
const ball_scene = preload("res://ball.tscn")

var balls: Array[Ball]
var balls_sunk: Array[int]
var cue_ball: Ball
var first_hit_scratch: bool

func init():
	create_balls()
	start_game()
	
func start_game():
	balls_sunk = [0, 0]
	cue_ball.reset(Vector3(-56, Constants.BALL_RADIUS, 0))
	place_rack(56, 0)
	
func end_round():
	first_hit_scratch = false
	cue_ball.first_hit_ball_num = -1
	
func get_cue_ball_global_pos():
	return cue_ball.global_position
	
func hit_cue_ball(force: Vector3, offset_3d: Vector3):
	cue_ball.apply_impulse(force, offset_3d)
	cue_ball.first_hit_ball_num = 0
	
func reset_cue_ball(pos: Vector3):
	cue_ball.reset(pos)
	
func play_cue_ball_sound(strength):
	var t: float = clamp(strength / 0.5, 0.0, 1.0)
	var volume_db: float = lerp(-25.0, 0.0, t)
	cue_ball.CueCollide.volume_db = volume_db
	cue_ball.CueCollide.pitch_scale = lerp(0.9, 1.1, t)
	cue_ball.CueCollide.play()
	
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
		ball.ball_num = i
		ball.name = "Ball%s" % i
		
		start_synchronizing_ball.rpc(ball.get_name())
		rpc_color_ball.rpc(ball.get_name())
		
		add_child(ball)
		balls.append(ball)
		
		if i == 0:
			cue_ball = ball
			cue_ball.body_entered.connect(cue_ball._on_body_entered)
			cue_ball.contact_monitor = true
			cue_ball.max_contacts_reported = 3
		else:
			ball.collision_layer += 1 << 2

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
	
func check_all_not_moving() -> bool:
	for ball in balls:
		if ball.get_linear_velocity().length() > SPEED_THRESH \
		or ball.get_angular_velocity().length() > ANGULAR_SPEED_THRESH:
			return false
	return true
	
func pot_all_solids():
	for ball in balls:
		if ball.is_solid():
			process_fallen_ball(ball)
	
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
		return true
	if scores[player_ind] >= Constants.BALLS_BEFORE_EIGHT:
		return ball_num == 8
	if player_ind == solids_player:
		return 1 <= ball_num and ball_num <= 7
	else:
		return 9 <= ball_num and ball_num <= 15

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

@rpc("authority", "call_local", "reliable")
func rpc_color_ball(ball_name: String) -> void:
	var ball_node = get_node(ball_name)
	color_ball(ball_node)
	
