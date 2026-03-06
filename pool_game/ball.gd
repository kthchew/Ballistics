extends RigidBody3D

var last_vel: Vector3 = Vector3(0, 0, 0)
var ball_num: int = 0
var first_hit_ball_num: int = -1
var teleport_requested: bool = false
var teleport_pos: Vector3 = Vector3.ZERO

var closest_dist_ever_to_hole: float = 1e308

func _ready() -> void:
	closest_dist_ever_to_hole = min(distance_to_closest_hole(), closest_dist_ever_to_hole)

func teleport(pos: Vector3) -> void:
	teleport_requested = true
	teleport_pos = pos

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if teleport_requested:
		teleport_requested = false
		var new_transform = state.transform
		new_transform.origin = teleport_pos
		state.transform = new_transform

@onready var ai_controller = $"../AIController3D"
@onready var holes = $"../TableGroup/Table/Holes"
#@onready var ai_controller = $AIController3D
#@onready var holes = $TableGroup/Table/Holes

func reset():
	position = Vector3(-56.0, 2.85, 0)
	linear_velocity = Vector3(0, 0, 0)
	angular_velocity = Vector3(0, 0, 0)	
	freeze = false
	show()

func _physics_process(delta):
	#if is_cue_ball() and linear_velocity.length() != 0 and last_vel.length() < 0.01:
		#print("Cue ball velocity: " + str(linear_velocity))
	
	last_vel = linear_velocity
	var friction_accel := 2

	linear_velocity = linear_velocity.move_toward(Vector3.ZERO, friction_accel * delta)
	angular_velocity = angular_velocity.move_toward(Vector3.ZERO, friction_accel * delta)

	if linear_velocity.length() < 0.05:
		linear_velocity = Vector3.ZERO

	if angular_velocity.length() < 0.1:
		angular_velocity = Vector3.ZERO
		
	if linear_velocity == Vector3.ZERO and angular_velocity == Vector3.ZERO:
		var current_dist = distance_to_closest_hole()
		if current_dist != closest_dist_ever_to_hole and not is_cue_ball():
			var relevant_dist_change = min(closest_dist_ever_to_hole, 30) - min(current_dist, 30)
			if relevant_dist_change > 0.001:
				if is_solid() or (is_eight_ball() and $"..".balls_sunk[0] == 7):
					# give reward if within 30 units of a hole, more reward if getting closer, range [0, 0.5]
					#print("giving " + str(relevant_dist_change / 30 / 2) + "reward")
					ai_controller.reward += relevant_dist_change / 30 / 2
				# give punishment if within 30 units of a hole, more punishment if getting closer, range [0, 0.5]
				elif is_stripe():
					#print("taking " + str(relevant_dist_change / 30 / 4) + "reward")
					ai_controller.reward -= relevant_dist_change / 30 / 2
					
		closest_dist_ever_to_hole = min(current_dist, closest_dist_ever_to_hole)

func is_cue_ball():
	return ball_num == 0

func is_solid():
	return 0 < ball_num and ball_num < 8
	
func is_eight_ball():
	return ball_num == 8
	
func is_stripe():
	return ball_num > 8
	
func distance_to_closest_hole():
	if not visible:
		return 0
	var dist = 9999
	for hole in holes.get_children():
		var hole_dist = hole.global_position.distance_to(global_position)
		if hole_dist < dist:
			dist = hole_dist
	return dist

func _on_body_entered(body: Node) -> void:
	#print("Collision with cue ball: " + body.name)
	if first_hit_ball_num <= 0 and body.name.contains("Ball"):
		first_hit_ball_num = body.ball_num
		ai_controller.reward -= 0.2
		if body.ball_num < 8 or (body.ball_num == 8 and $"..".balls_sunk[0] == 7):
			ai_controller.reward += 0.23
