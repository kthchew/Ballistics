extends Node

signal ai_aimed(dir: Vector2)

@onready var shape_cast = $/root/Main/ShapeCast3D

var hole_locs: Array[Vector3]
var ghost_circle: Node2D
var hole_circle: Node2D

func _on_ghost_circle_draw():
	ghost_circle.draw_circle(Vector2(0, 0), 10.0, Color.TOMATO)
	
func _on_hole_circle_draw():
	hole_circle.draw_circle(Vector2(0, 0), 10.0, Color.BLUE_VIOLET)

func _ready():
	ghost_circle = Node2D.new()
	ghost_circle.draw.connect(_on_ghost_circle_draw)
	add_child(ghost_circle)
	hole_circle = Node2D.new()
	hole_circle.draw.connect(_on_hole_circle_draw)
	add_child(hole_circle)
	
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
	
func shoot(cue_ball: Ball, obj_ball: Ball, hole_loc: Vector3):
	var force = calc_shot(cue_ball, obj_ball, hole_loc)
	var ghost_ball_pos = calc_ghost_ball_pos(cue_ball, obj_ball, hole_loc)
	print("ai ghost pos ", ghost_ball_pos)
	
	var camera = $/root/Main/CameraPivot/Camera3D
	ghost_circle.position = camera.unproject_position(ghost_ball_pos)
	ghost_circle.queue_redraw()
	hole_circle.position = camera.unproject_position(hole_loc)
	hole_circle.queue_redraw()
	
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

func find_shots(cue_ball: Ball, obj_balls: Array[Ball]):
	await get_tree().create_timer(1.0).timeout
	var candidates = []
	for obj_ball in obj_balls:
		if obj_ball.potted or obj_ball == cue_ball:
			continue
		for i in range(6):
			var hole_loc = hole_locs[i]
			if await find_shot(cue_ball, obj_ball, hole_loc):
				print("choosing shot: ball num=", obj_ball.ball_num, " hole loc=", hole_loc)
				shoot(cue_ball, obj_ball, hole_loc)
				return
				
	print("AI didn't find any shots")
	shoot(cue_ball, obj_balls[1], hole_locs[0])

func find_shot(cue_ball: Ball, obj_ball: Ball, hole_loc: Vector3) -> bool:
	var hole_path_clear = shapecast_to_hole(obj_ball, hole_loc)
	#await get_tree().create_timer(1.0).timeout
	var cue_ball_path_clear = shapecast_to_cue_ball(cue_ball, obj_ball, hole_loc)
	#await get_tree().create_timer(1.0).timeout
	return hole_path_clear and cue_ball_path_clear
	
func shapecast_to_hole(obj_ball: Ball, hole_loc: Vector3):
	var origin = obj_ball.global_position
	shape_cast.global_position = origin
	shape_cast.max_results = 1
	shape_cast.target_position = hole_loc - origin
	shape_cast.collision_mask = 1 << 2
	shape_cast.force_shapecast_update()
	
	var safe_frac = shape_cast.get_closest_collision_safe_fraction()
	print("shapecast to hole: ", obj_ball.ball_num, " ", hole_loc, " safe frac ", safe_frac)
	return safe_frac > 0.99
	
func shapecast_to_cue_ball(cue_ball: Ball, obj_ball: Ball, hole_loc: Vector3) -> bool:
	var origin = cue_ball.global_position
	var ghost_ball_pos = calc_ghost_ball_pos(cue_ball, obj_ball, hole_loc)
	shape_cast.global_position = origin
	shape_cast.max_results = 1
	shape_cast.target_position = ghost_ball_pos - origin
	shape_cast.collision_mask = 1 << 2
	shape_cast.force_shapecast_update()
	
	var safe_frac = shape_cast.get_closest_collision_safe_fraction()
	print("shape casting to cue ball: ", obj_ball.ball_num, " safe frac ", safe_frac)
	return safe_frac > 0.99
