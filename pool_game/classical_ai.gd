extends Node

signal ai_aimed(dir: Vector2)
signal ai_placed_cue_ball(pos: Vector3)
signal ai_picked_pocket(hole_ind: int)

@onready var camera = $/root/Main/CameraPivot/Camera3D

var hole_locs: Array[Vector3]
var cached_shot: Shot

func _ready():
	fill_hole_locs()
	cached_shot = null
	Shot.shape_cast = $/root/Main/ShapeCast3D

func fill_hole_locs():
	hole_locs = []
	var hole_rad = 1.5
	var dx = [-1, 1, 0, 0]
	var dz = [0, 0, -1, 1]
	var aberration_strengths = [1, 2, 3]
	for hole_ind in range(6):
		var path_str = "/root/Main/TableGroup/Table/Holes/Hole" + str(hole_ind + 1) + "/HoleMarker"
		var hole_marker = get_node(path_str)
		var pos = hole_marker.global_position
		pos.y = Constants.BALL_RADIUS
		hole_locs.append(pos)
		for aberration_strength in aberration_strengths:
			for aberration_ind in range(len(dx)):
				var x_move = hole_rad * aberration_strength * dx[aberration_ind]
				var z_move = hole_rad * aberration_strength * dz[aberration_ind]
				hole_locs.append(pos + Vector3(x_move, 0, z_move))

func calc_ghost_ball_pos(obj_ball: Ball, target_pos: Vector3, mult: float = 1.0) -> Vector3:
	var target_to_obj_dir = obj_ball.global_position - target_pos
	target_to_obj_dir.y = 0
	target_to_obj_dir = target_to_obj_dir.normalized()
	var ghost_ball_pos = obj_ball.global_position + mult * (2 * Constants.BALL_RADIUS * target_to_obj_dir)
	return ghost_ball_pos
	
func calc_shot_dir(cue_ball: Ball, target_pos: Vector3) -> Vector3:
	var dir = (cue_ball.global_position - target_pos).normalized()
	return dir
	
func calc_ai_color(ball_ind: int, obj_ball_cnt: int) -> Color:
	return Color.PURPLE + (ball_ind - obj_ball_cnt) * 0.15 * Color(1, 1, 1)
	
func highlight_ball(obj_ball: Ball, color: Color):
	var mesh = obj_ball.get_node("MeshInstance3D")
	var outline_material = StandardMaterial3D.new()
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.albedo_color = color
	outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
	outline_material.grow = true
	outline_material.grow_amount = 1
	mesh.material_overlay = outline_material
	
func pick_pocket():
	if cached_shot.potting:
		var hole_ind = Shot.calc_hole_ind_from_pos(cached_shot.hole_loc)
		ai_picked_pocket.emit(hole_ind)
	else:
		ai_picked_pocket.emit(0)
	
func place_cue_ball():
	var cue_ball_target = cached_shot.target_positions[0]
	var first_ball = cached_shot.obj_balls[0]
	var place_pos = Shot.calc_ghost_ball_pos(first_ball, cue_ball_target, -2)
	ai_placed_cue_ball.emit(place_pos)
	
func shoot():
	print("Shooting shot: ")
	print_shot(cached_shot)
	for i in range(len(cached_shot.obj_balls)):
		var color = Color.YELLOW
		if cached_shot.potting:
			color = calc_ai_color(i, len(cached_shot.obj_balls))
		highlight_ball(cached_shot.obj_balls[i], color)
	
	for i in range(len(cached_shot.target_positions)):
		var color = Color.YELLOW
		if len(cached_shot.obj_balls) == 0:
			color = Color.RED
		if cached_shot.potting:
			color = calc_ai_color(i, len(cached_shot.obj_balls))
		Draw.circle(camera.unproject_position(cached_shot.target_positions[i]), 10.0, color)
	
	var cue_ball_target = cached_shot.target_positions[0]
	var shot_dir = calc_shot_dir(cached_shot.cue_ball, cue_ball_target)
	var shot_dir_2d = Vector2(-shot_dir.x, -shot_dir.z)
	ai_aimed.emit(shot_dir_2d, cached_shot.power)

func generate_ball_perms(obj_balls: Array[Ball]) -> Array:
	var ans = []
	# comment this loop out to test only 2 ball shots
	for i in range(len(obj_balls)):
		ans.append([obj_balls[i]])
		
	for i in range(len(obj_balls)):
		for j in range(len(obj_balls)):
			if i == j:
				continue
			ans.append([obj_balls[i], obj_balls[j]])
	
	return ans
	
func print_shot(shot: Shot):
	print("Shot:")
	for i in range(len(shot.obj_balls)):
		print("\tobj ball num ", i, "=", shot.obj_balls[i].ball_num)
	print("\thole loc=", shot.hole_loc)
	print("\tpower=", shot.power)

func reset_shot():
	cached_shot = null

func find_shot(cue_ball: Ball, obj_balls: Array[Ball]):
	Draw.clear_all()
	if cached_shot != null:
		return
	
	if find_potting_shot(cue_ball, obj_balls):
		return
	
	if find_non_potting_shot(cue_ball, obj_balls):
		return
	
	print("Choosing random shot")
	choose_random_shot(cue_ball)
	
func choose_random_shot(cue_ball: Ball):
	var shot = Shot.new(cue_ball, [], Vector3.INF, camera)
	var angle = randf_range(0, 2 * 3.14)
	shot.target_positions.append(
		cue_ball.global_position + 2 * Constants.BALL_RADIUS * Vector3(cos(angle), 0, -sin(angle))
	)
	print_shot(shot)
	cached_shot = shot
	
func prefers_alt_shot(alt_shot: Shot, cached_shot: Shot) -> bool:
	return alt_shot.poss and (cached_shot == null or alt_shot.goodness > cached_shot.goodness)
	
func find_potting_shot(cue_ball: Ball, obj_balls: Array[Ball]) -> bool:
	var perms = generate_ball_perms(obj_balls)
	for perm in perms:
		for hole_loc in hole_locs:
			var alt_shot = Shot.new(cue_ball, perm, hole_loc, camera)
			if prefers_alt_shot(alt_shot, cached_shot):
				print("Prefer alternative shot: ")
				print_shot(alt_shot)
				cached_shot = alt_shot
	return cached_shot != null
	
func find_non_potting_shot(cue_ball: Ball, obj_balls: Array[Ball]) -> bool:
	for obj_ball in obj_balls:
		var alt_shot = Shot.new(cue_ball, [obj_ball], Vector3.INF, camera)
		if prefers_alt_shot(alt_shot, cached_shot):
			print("Prefer alternative shot: ")
			print_shot(alt_shot)
			cached_shot = alt_shot
	return cached_shot != null
