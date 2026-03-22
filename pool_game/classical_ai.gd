extends Node

signal ai_aimed(dir: Vector2)
signal ai_placed_cue_ball(pos: Vector3)

@onready var shape_cast = $/root/Main/ShapeCast3D
@onready var camera = $/root/Main/CameraPivot/Camera3D

var hole_locs: Array[Vector3]
var found_shot: bool = true

func _ready():
	fill_hole_locs()
			
func fill_hole_locs():
	hole_locs = []
	var hole_rad = 3
	var dx = [-1, 1, 0, 0]
	var dz = [0, 0, -1, 1]
	for hole_ind in range(6):
		var path_str = "/root/Main/TableGroup/Table/Holes/Hole" + str(hole_ind + 1) + "/HoleMarker"
		var hole_marker = get_node(path_str)
		var pos = hole_marker.global_position
		pos.y = Constants.BALL_RADIUS
		for aberration_ind in range(len(dx)):
			var x_move = hole_rad * dx[aberration_ind]
			var z_move = hole_rad * dz[aberration_ind]
			hole_locs.append(pos + Vector3(x_move, 0, z_move))

func calc_ghost_ball_pos(obj_ball: Ball, target_pos: Vector3) -> Vector3:
	var target_to_obj_dir = obj_ball.global_position - target_pos
	target_to_obj_dir.y = 0
	target_to_obj_dir = target_to_obj_dir.normalized()
	var ghost_ball_pos = obj_ball.global_position + (2 * Constants.BALL_RADIUS * target_to_obj_dir)
	return ghost_ball_pos
	
func calc_shot(cue_ball: Ball, target_pos: Vector3):
	var dir = (cue_ball.global_position - target_pos).normalized()
	var strength = 100
	return strength * dir
	
func highlight_ball(obj_ball: Ball):
	var mesh = obj_ball.get_node("MeshInstance3D")
	var highlight_material = StandardMaterial3D.new()
	highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight_material.albedo_color = Color(1.0, 1.0, 1.0, 0.5)
	mesh.material_overlay = highlight_material
	
# target_pos = point that cue ball should move toward
func shoot(cue_ball: Ball, obj_balls: Array[Ball], target_pos: Vector3, scratched: bool):
	var first_ball = obj_balls[0]
	if scratched:
		var place_pos = first_ball.global_position + 2 * (target_pos - first_ball.global_position)
		ai_placed_cue_ball.emit(place_pos)
	
	for obj_ball in obj_balls:
		highlight_ball(obj_ball)
	
	var force = calc_shot(cue_ball, target_pos)
	ai_aimed.emit(Vector2(-force.x, -force.z))
	
	return

func generate_ball_perms(obj_balls: Array[Ball]) -> Array:
	var ans = []
	
	# comment this loop out to test only 2 ball shots
	#for i in range(len(obj_balls)):
		#ans.append([obj_balls[i]])
	
	for i in range(len(obj_balls)):
		for j in range(len(obj_balls)):
			if i == j:
				continue
			ans.append([obj_balls[i], obj_balls[j]])
	
	return ans
	
func print_shot(obj_balls: Array[Ball], hole_loc: Vector3):
	print("Shot:")
	for i in range(len(obj_balls)):
		print("\tobj ball num ", i, "=", obj_balls[i].ball_num)
	print("\thole loc=", hole_loc)

func find_shots(cue_ball: Ball, obj_balls: Array[Ball], scratched: bool):
	await get_tree().create_timer(1.0).timeout
	
	var perms = generate_ball_perms(obj_balls)
	for perm in perms:
		for hole_loc in hole_locs:
			Draw.clear_all()
			var shot = await find_shot(cue_ball, perm, hole_loc, scratched)
			var shot_poss = shot[0]
			var shot_target_pos = shot[1]
			if shot_poss:
				print_shot(perm, hole_loc)
				shoot(cue_ball, perm, shot_target_pos, scratched)
				return
	
	Draw.clear_all()
				
	var shot = find_non_potting_shot(cue_ball, obj_balls)
	var shot_poss = shot[0]
	var shot_target_pos = shot[1]
	if shot_poss:
		shoot(cue_ball, obj_balls, shot_target_pos, scratched)
		return
	
# find a shot just to touch a valid ball so that it's not a scratch
func find_non_potting_shot(cue_ball: Ball, obj_balls: Array[Ball]):
	for obj_ball in obj_balls:
		if shapecast_ball(cue_ball, obj_ball.global_position):
			return [true, obj_ball.global_position]
	return [false, Vector3.ZERO]

func find_shot(cue_ball: Ball, obj_balls: Array, hole_loc: Vector3, scratched: bool) -> Array:
	var target_pos = hole_loc
	Draw.circle(camera.unproject_position(target_pos), 10, Color.GREEN)
	for i in range(len(obj_balls) - 1, -1, -1):
		
		if not shapecast_ball(obj_balls[i], target_pos):
			return [false, Vector3.ZERO]
		
		target_pos = calc_ghost_ball_pos(obj_balls[i], target_pos)
		Draw.circle(camera.unproject_position(target_pos), 10, Color.GREEN)
	
	var cue_ball_path_clear
	if not scratched:
		cue_ball_path_clear = shapecast_ball(cue_ball, target_pos)
	else:
		cue_ball_path_clear = shapecast_placing_cue_ball(obj_balls[0], target_pos)
	
	return [cue_ball_path_clear, target_pos]
	
func shapecast(origin: Vector3, abs_target: Vector3) -> float:
	shape_cast.global_position = origin
	shape_cast.max_results = 1
	shape_cast.target_position = abs_target - origin
	shape_cast.collision_mask = 1 << 2
	shape_cast.force_shapecast_update()
	return shape_cast.get_closest_collision_safe_fraction()
	
func shapecast_ball(ball: Ball, target_pos: Vector3) -> bool:
	var ball_pos = ball.global_position
	var safe_frac = shapecast(ball_pos, target_pos)
	print("Shape casting",
		"\n\tball num=", ball.ball_num, 
		"\n\tto target_pos=", target_pos, 
		"\n\tsafe frac=", safe_frac
	)
	return safe_frac > 0.99
	
func shapecast_placing_cue_ball(obj_ball: Ball, target_pos: Vector3) -> bool:
	var ghost_ball_pos = calc_ghost_ball_pos(obj_ball, target_pos)
	var start_pos = obj_ball.global_position + 2 * (ghost_ball_pos - obj_ball.global_position)
	var safe_frac = shapecast(start_pos, ghost_ball_pos)
	print("shape casting placing cue ball after scratch: ", obj_ball.ball_num, ", safe frac ", safe_frac)
	return safe_frac > 0.99
