class_name Shot extends Node

static var shape_cast: ShapeCast3D

var cue_ball: Ball
var obj_balls: Array
var hole_loc: Vector3
var scratched: bool
var poss: bool
var target_positions: Array[Vector3]
var potting: bool
var power: float
var goodness: float

@onready var camera = $/root/Main/CameraPivot/Camera3D

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
	
func shapecast(origin: Vector3, abs_target: Vector3) -> bool:
	shape_cast.global_position = origin
	shape_cast.max_results = 1
	shape_cast.target_position = abs_target - origin
	shape_cast.collision_mask = 1 << 2
	shape_cast.force_shapecast_update()

	var safe_frac = shape_cast.get_closest_collision_safe_fraction()
	return safe_frac > 0.99
	
func shapecast_in_place(pos: Vector3) -> bool:
	shape_cast.global_position = pos
	shape_cast.max_results = 1
	shape_cast.target_position = Vector3.ZERO
	shape_cast.collision_mask = 1 << 2
	shape_cast.force_shapecast_update()
	
	#Draw.circle(camera.unproject_position(pos), 10, Color.BLUE)
	
	var colliding = shape_cast.is_colliding()
	return not colliding
	
func shapecast_ball(ball: Ball, target_pos: Vector3) -> bool:
	var ball_pos = ball.global_position
	var path_is_clear = shapecast(ball_pos, target_pos)
	
	#print("Shape casting",
		#"\n\tball num=", ball.ball_num, 
		#"\n\tto target_pos=", target_pos, 
		#"\n\tsafe frac=", safe_frac
	#)
	#Draw.circle(camera.unproject_position(shape_cast.get_collision_point(0)), 5, Color.TOMATO)
	#Draw.circle(camera.unproject_position(target_pos), 5, Color.BLUE)
	
	return path_is_clear
	
func shapecast_placing_cue_ball(obj_ball: Ball, target_pos: Vector3) -> bool:
	var start_pos = calc_ghost_ball_pos(obj_ball, target_pos, -2.0)
	var path_is_clear = shapecast(start_pos, target_pos) and shapecast_in_place(start_pos)
	print("shape casting placing cue ball after scratch: obj ball num=", obj_ball.ball_num, ", path_is_clear=", path_is_clear)
	#Draw.circle(camera.unproject_position(start_pos), 5, Color.RED)
	#Draw.circle(camera.unproject_position(target_pos), 5, Color.RED)
	return path_is_clear

func _init(cue_ball: Ball, obj_balls: Array, hole_loc: Vector3, camera):
	self.cue_ball = cue_ball
	self.obj_balls = obj_balls
	self.hole_loc = hole_loc
	self.scratched = cue_ball.potted
	self.potting = hole_loc != Vector3.INF
	self.camera = camera
	if self.potting:
		self.poss = check_pot_possible()
	elif len(obj_balls) > 0:
		self.poss = check_non_pot_possible()
	else:
		self.poss = true
	self.power = calc_power()
	self.goodness = 1 / self.power
	
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
		
func calc_power() -> float:
	if self.obj_balls.is_empty():
		return 50
		
	var cur_pos = self.cue_ball.global_position
	var total_dist = 0
	
	var cum_mom_trans = 1
	var prev_vec: Vector3 = Vector3.INF
	var cur_vec: Vector3 = Vector3.INF
	
	for target_pos in self.target_positions:
		var dist = cur_pos.distance_to(target_pos)
		total_dist += dist
		
		cur_vec = (target_pos - cur_pos).normalized()
		if prev_vec != Vector3.INF:
			var mom_trans = cur_vec.dot(prev_vec)
			# TODO: mom_trans was negative once??
			cum_mom_trans *= mom_trans
		prev_vec = cur_vec
		cur_pos = target_pos
		
	#print("total_dist = ", total_dist)
	#print("cum_mom_trans = ", cum_mom_trans)
	var power = lerp(20, 100, total_dist / (500 * cum_mom_trans))
	#print("power = ", power)
	var clamped_power = clamp(power, 10, 100)
	return clamped_power
