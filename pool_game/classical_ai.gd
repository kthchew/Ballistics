extends Node

@onready var shape_cast = $/root/Main/ShapeCast3D

var hole_locs: Array[Vector3]

func _ready():
	hole_locs = []
	for i in range(6):
		var path_str = "/root/Main/TableGroup/Table/Holes/Hole" + str(i + 1) + "/HoleMarker"
		var hole_marker = get_node(path_str)
		hole_locs.append(hole_marker.global_position)
	

func find_shots(cue_ball: Ball, obj_balls: Array[Ball]):
	var candidates = []
	for obj_ball in obj_balls:
		if obj_ball == cue_ball:
			continue
		for hole_loc in hole_locs:
			find_shot(cue_ball, obj_ball, hole_loc)
			

func find_shot(cue_ball: Ball, obj_ball: Ball, hole_loc: Vector3) -> bool:
	var hole_path_clear = shapecast_to_hole(obj_ball, hole_loc)
	var cue_ball_path_clear = shapecast_to_cue_ball(cue_ball, obj_ball)
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
		#var force = Vector3(hole_loc - origin)
		#force.y = 0
		#obj_ball.apply_central_force(100 * force)
		#print("applying force ", force)
		#return true
	return false
	
func shapecast_to_cue_ball(cue_ball: Ball, obj_ball: Ball) -> bool:
	var origin = obj_ball.global_position
	shape_cast.global_position = origin
	shape_cast.max_results = 1
	shape_cast.target_position = cue_ball.global_position - origin
	shape_cast.collision_mask = 1 << 2
	shape_cast.exclude_parent = true
	
	shape_cast.force_shapecast_update()
	var safe_frac = shape_cast.get_closest_collision_safe_fraction()
	print("shape casting to cue ball: ", obj_ball.ball_num, " safe frac ", safe_frac)
	return safe_frac > 0.99
		#var force = Vector3(hole_loc - origin)
		#force.y = 0
		#obj_ball.apply_central_force(100 * force)
		#print("applying force", force)
		#return true
	#return false
	
	
