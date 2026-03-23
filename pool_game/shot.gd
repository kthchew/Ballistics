class_name Shot extends Node

static var shape_cast: ShapeCast3D

var cue_ball: Ball
var obj_balls: Array
var hole_loc: Vector3
var scratched: bool
var poss: bool
var target_positions: Array[Vector3]
var potting: bool

static func calc_hole_ind_from_pos(pos: Vector3) -> int:
	var hole_ind = 0
	if pos.z > 0:
		hole_ind += 3
	
	if pos.x > 50.91:
		hole_ind += 2
	elif pos.x > -50.91:
		hole_ind += 1
	
	return hole_ind

static func calc_ghost_ball_pos(obj_ball: Ball, target_pos: Vector3, mult: float = 1.0) -> Vector3:
	var target_to_obj_dir = obj_ball.global_position - target_pos
	target_to_obj_dir.y = 0
	target_to_obj_dir = target_to_obj_dir.normalized()
	var ghost_ball_pos = obj_ball.global_position + mult * (2 * Constants.BALL_RADIUS * target_to_obj_dir)
	return ghost_ball_pos
	
static func shapecast(origin: Vector3, abs_target: Vector3) -> float:
	shape_cast.global_position = origin
	shape_cast.max_results = 1
	shape_cast.target_position = abs_target - origin
	shape_cast.collision_mask = 1 << 2
	shape_cast.force_shapecast_update()
	return shape_cast.get_closest_collision_safe_fraction()
	
static func shapecast_ball(ball: Ball, target_pos: Vector3) -> bool:
	var ball_pos = ball.global_position
	var safe_frac = shapecast(ball_pos, target_pos)
	print("Shape casting",
		"\n\tball num=", ball.ball_num, 
		"\n\tto target_pos=", target_pos, 
		"\n\tsafe frac=", safe_frac
	)
	return safe_frac > 0.99
	
static func shapecast_placing_cue_ball(obj_ball: Ball, target_pos: Vector3) -> bool:
	var ghost_ball_pos = calc_ghost_ball_pos(obj_ball, target_pos)
	var start_pos = calc_ghost_ball_pos(obj_ball, target_pos, 2.0)
	var safe_frac = shapecast(start_pos, ghost_ball_pos)
	print("shape casting placing cue ball after scratch: ", obj_ball.ball_num, ", safe frac ", safe_frac)
	return safe_frac > 0.99

func _init(cue_ball: Ball, obj_balls: Array, hole_loc: Vector3):
	self.cue_ball = cue_ball
	self.obj_balls = obj_balls
	self.hole_loc = hole_loc
	self.scratched = cue_ball.potted
	self.potting = hole_loc != Vector3.INF
	if self.potting:
		self.poss = check_pot_possible()
	elif len(obj_balls) > 0:
		self.poss = check_non_pot_possible()
	else:
		self.poss = true
	
func check_pot_possible() -> bool:
	var target_pos = hole_loc
		
	self.target_positions.append(target_pos)
	for i in range(len(obj_balls) - 1, -1, -1):
		
		if not shapecast_ball(obj_balls[i], target_pos):
			return false
		
		target_pos = calc_ghost_ball_pos(obj_balls[i], target_pos)
		self.target_positions.append(target_pos)
		
	self.target_positions.reverse()
	
	var cue_ball_path_clear
	if not scratched:
		cue_ball_path_clear = shapecast_ball(cue_ball, target_pos)
	else:
		cue_ball_path_clear = shapecast_placing_cue_ball(obj_balls[0], target_pos)
	
	return cue_ball_path_clear
	
func check_non_pot_possible() -> bool:
	if scratched:
		var obj_ball = obj_balls[0]
		var obj_target = obj_ball.global_position + Vector3(0, 0, 2 * Constants.BALL_RADIUS)
		var cue_target = calc_ghost_ball_pos(obj_ball, obj_target)
		self.target_positions.append(cue_target)
		return shapecast_placing_cue_ball(obj_ball, obj_target)
	else:
		var cue_target_pos = calc_ghost_ball_pos(obj_balls[0], cue_ball.global_position, -1)
		self.target_positions.append(cue_target_pos)
		return shapecast_ball(cue_ball, cue_target_pos)
