extends Node

signal ai_aimed(dir: Vector2)
signal ai_placed_cue_ball(pos: Vector3)

@onready var shape_cast = $/root/Main/ShapeCast3D

var hole_locs: Array[Vector3]
var ghost_circle: Node2D
var hole_circle: Node2D
var found_shot: bool = true

func _on_ghost_circle_draw():
	ghost_circle.draw_circle(Vector2(0, 0), 10.0, Color.TOMATO)
	
func _on_hole_circle_draw():
	var color = Color.GREEN
	if not found_shot:
		color = Color.RED
	hole_circle.draw_circle(Vector2(0, 0), 10.0, color)

func _ready():
	ghost_circle = Node2D.new()
	ghost_circle.draw.connect(_on_ghost_circle_draw)
	add_child(ghost_circle)
	hole_circle = Node2D.new()
	hole_circle.draw.connect(_on_hole_circle_draw)
	add_child(hole_circle)
	
	hole_locs = []
	
	var hole_rad = 3
	var dx = [-1, 1, 0, 0]
	var dz = [0, 0, -1, 1]
	for hole_ind in range(6):
		var path_str = "/root/Main/TableGroup/Table/Holes/Hole" + str(hole_ind + 1) + "/HoleMarker"
		var hole_marker = get_node(path_str)
		var pos = hole_marker.global_position
		hole_locs.append(pos)
		for aberration_ind in range(len(dx)):
			var x_move = hole_rad * dx[aberration_ind]
			var z_move = hole_rad * dz[aberration_ind]
			hole_locs.append(pos + Vector3(x_move, 0, z_move))

func calc_ghost_ball_pos(obj_ball: Ball, hole_loc: Vector3, mult: float = 1.0) -> Vector3:
	var hole_to_obj_dir = obj_ball.global_position - hole_loc
	hole_to_obj_dir.y = 0
	hole_to_obj_dir = hole_to_obj_dir.normalized()
	var ghost_ball_pos = obj_ball.global_position + mult * (2 * Constants.BALL_RADIUS * hole_to_obj_dir)
	return ghost_ball_pos
	
func calc_shot(cue_ball: Ball, obj_ball: Ball, hole_loc: Vector3):
	var ghost_ball_pos = calc_ghost_ball_pos(obj_ball, hole_loc)
	var dir = (cue_ball.global_position - ghost_ball_pos).normalized()
	var strength = 100
	return strength * dir
	
func shoot(cue_ball: Ball, obj_ball: Ball, hole_loc: Vector3, scratched: bool):
	if scratched:
		var place_pos = calc_ghost_ball_pos(obj_ball, hole_loc, 2.0)
		ai_placed_cue_ball.emit(place_pos)
		
	var force = calc_shot(cue_ball, obj_ball, hole_loc)
	var ghost_ball_pos = calc_ghost_ball_pos(obj_ball, hole_loc)
	print("ai ghost pos ", ghost_ball_pos)
	
	var camera = $/root/Main/CameraPivot/Camera3D
	ghost_circle.position = camera.unproject_position(ghost_ball_pos)
	ghost_circle.queue_redraw()
	hole_circle.position = camera.unproject_position(hole_loc)
	hole_circle.queue_redraw()
	
	# highlight target object ball
	var mesh = obj_ball.get_node("MeshInstance3D")
	var highlight_material = StandardMaterial3D.new()
	highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight_material.albedo_color = Color(1.0, 1.0, 0.0, 0.3) # Transparent yellow
	highlight_material.emission_enabled = true
	highlight_material.emission = Color(1.0, 0.0, 0.0)
	highlight_material.emission_energy_multiplier = 2.0
	
	mesh.material_overlay = highlight_material
	
	ai_aimed.emit(Vector2(-force.x, -force.z))
	return

func find_shots(cue_ball: Ball, obj_balls: Array[Ball], scratched: bool):
	await get_tree().create_timer(1.0).timeout
	var candidates = []
	for obj_ball in obj_balls:
		if obj_ball.potted or obj_ball == cue_ball:
			continue
		for hole_loc in hole_locs:
			if await find_shot(cue_ball, obj_ball, hole_loc, scratched):
				print("choosing shot: ball num=", obj_ball.ball_num, ", hole loc=", hole_loc)
				found_shot = true
				shoot(cue_ball, obj_ball, hole_loc, scratched)
				return
				
	print("AI didn't find any shots")
	var rand_ball_ind = randi_range(0, len(obj_balls) - 1)
	var rand_hole_loc = randi_range(0, len(hole_locs) - 1)
	print(hole_locs)
	found_shot = false
	
	shoot(cue_ball, obj_balls[rand_ball_ind], hole_locs[rand_hole_loc], scratched)

func find_shot(cue_ball: Ball, obj_ball: Ball, hole_loc: Vector3, scratched: bool) -> bool:
	var hole_path_clear = shapecast_to_hole(obj_ball, hole_loc)
	#await get_tree().create_timer(1.0).timeout
	var cue_ball_path_clear;
	if not scratched:
		cue_ball_path_clear = shapecast_to_cue_ball(cue_ball, obj_ball, hole_loc)
	else:
		cue_ball_path_clear = shapecast_placing_cue_ball(obj_ball, hole_loc)
	#await get_tree().create_timer(1.0).timeout
	return hole_path_clear and cue_ball_path_clear
	
func shapecast(origin: Vector3, target_position: Vector3) -> float:
	shape_cast.global_position = origin
	shape_cast.max_results = 1
	shape_cast.target_position = target_position
	shape_cast.collision_mask = 1 << 2
	shape_cast.force_shapecast_update()
	return shape_cast.get_closest_collision_safe_fraction()
	
func shapecast_to_hole(obj_ball: Ball, hole_loc: Vector3):
	var obj_ball_pos = obj_ball.global_position
	var safe_frac = shapecast(obj_ball_pos, hole_loc - obj_ball_pos)
	print("shapecast to hole: object ball num=", obj_ball.ball_num, ", hole_loc=", hole_loc, ", safe frac=", safe_frac)
	return safe_frac > 0.99
	
func shapecast_to_cue_ball(cue_ball: Ball, obj_ball: Ball, hole_loc: Vector3) -> bool:
	var cue_ball_pos = cue_ball.global_position
	var ghost_ball_pos = calc_ghost_ball_pos(obj_ball, hole_loc)
	var safe_frac = shapecast(cue_ball_pos, ghost_ball_pos - cue_ball_pos)
	print("shape casting to cue ball: object ball num=", obj_ball.ball_num, ", safe frac=", safe_frac)
	return safe_frac > 0.99
	
func shapecast_placing_cue_ball(obj_ball: Ball, hole_loc: Vector3) -> bool:
	var ghost_ball_pos = calc_ghost_ball_pos(obj_ball, hole_loc)
	var start_pos = calc_ghost_ball_pos(obj_ball, hole_loc, 2.0)
	var safe_frac = shapecast(start_pos, ghost_ball_pos - start_pos)
	print("shape casting placing cue ball after scratch: ", obj_ball.ball_num, ", safe frac ", safe_frac)
	return safe_frac > 0.99
