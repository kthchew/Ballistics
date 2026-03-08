extends Node

@onready var shape_cast = $/root/Main/ShapeCast3D

var hole_locs: Array[Vector3]

func _ready():
	hole_locs = []
	for i in range(6):
		var path_str = "/root/Main/TableGroup/Table/Holes/Hole" + str(i + 1) + "/HoleMarker"
		var hole_marker = get_node(path_str)
		hole_locs.append(hole_marker.global_position)

func calc_ghost_ball_pos(cue_ball: Ball, obj_ball: Ball, hole_loc: Vector3) -> Vector3:
	var hole_to_obj_dir = obj_ball.global_position - hole_loc
	hole_to_obj_dir.y = 0
	hole_to_obj_dir = hole_to_obj_dir.normalized()
	var ghost_ball_pos = obj_ball.global_position + 2 * Constants.BALL_RADIUS * hole_to_obj_dir
	return ghost_ball_pos
	
func calc_shot(cue_ball: Ball, obj_ball: Ball, hole_loc: Vector3):
	var ghost_ball_pos = calc_ghost_ball_pos(cue_ball, obj_ball, hole_loc)
	var dir = (cue_ball.global_position - ghost_ball_pos).normalized()
	var strength = 100
	return strength * dir

func find_shots(cue_ball: Ball, obj_balls: Array[Ball]):
	var candidates = []
	for obj_ball in obj_balls:
		if obj_ball == cue_ball:
			continue
		for hole_loc in hole_locs:
			if find_shot(cue_ball, obj_ball, hole_loc):
				var force = calc_shot(cue_ball, obj_ball, hole_loc)
				return

func find_shot(cue_ball: Ball, obj_ball: Ball, hole_loc: Vector3) -> bool:
	var hole_path_clear = shapecast_to_hole(obj_ball, hole_loc)
	var cue_ball_path_clear = shapecast_to_cue_ball(cue_ball, obj_ball, hole_loc)
	return hole_path_clear and cue_ball_path_clear
	
func shapecast_to_hole(obj_ball: Ball, hole_loc: Vector3):
	var origin = obj_ball.global_position
	shape_cast.global_position = origin
	shape_cast.max_results = 1
	shape_cast.target_position = hole_loc - origin
	shape_cast.collision_mask = 1 << 2
	shape_cast.exclude_parent = true	
	shape_cast.force_shapecast_update()
	
	var safe_frac = shape_cast.get_closest_collision_safe_fraction()
	print("shapecast to hole: ", obj_ball.ball_num, " ", hole_loc, " safe frac", safe_frac)
	return safe_frac > 0.99
	
func shapecast_to_cue_ball(cue_ball: Ball, obj_ball: Ball, hole_loc: Vector3) -> bool:
	var origin = calc_ghost_ball_pos(cue_ball, obj_ball, hole_loc)
	shape_cast.global_position = origin
	shape_cast.max_results = 1
	shape_cast.target_position = cue_ball.global_position - origin
	shape_cast.collision_mask = 1 << 2
	shape_cast.exclude_parent = true
	shape_cast.force_shapecast_update()
	
	var safe_frac = shape_cast.get_closest_collision_safe_fraction()
	print("shape casting to cue ball: ", obj_ball.ball_num, " safe frac ", safe_frac)
	return safe_frac > 0.99
