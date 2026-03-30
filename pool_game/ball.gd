class_name Ball extends RigidBody3D

signal first_hit_ball_changed

var ball_num: int = 0
var first_hit_ball_num: int = -1
var teleport_requested: bool = false
var teleport_pos: Vector3 = Vector3.ZERO
var potted: bool = false

var printed_cnt: int = 0

func _ready() -> void:
	self.body_entered.connect(self._on_body_entered)

func teleport(pos: Vector3) -> void:
	teleport_requested = true
	teleport_pos = pos

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if teleport_requested:
		teleport_requested = false
		var new_transform = state.transform
		new_transform.origin = teleport_pos
		state.transform = new_transform
		
func reset(pos: Vector3):
	teleport(pos)
	linear_velocity = Vector3(0, 0, 0)
	angular_velocity = Vector3(0, 0, 0)
	rotation = Vector3(0, 0, 0)
	freeze = false
	potted = false
	first_hit_ball_num = -1
	show()

func pot():
	linear_velocity = Vector3(0, 0, 0)
	angular_velocity = Vector3(0, 0, 0)
	rotation = Vector3(PI / 2, 0, PI)
	freeze = true
	# position set manually + teleport are both needed for some reason
	var pos = Vector3(-42 + 2 * Constants.BALL_RADIUS * ball_num, 0, 68)
	position = pos
	teleport(pos)
	potted = true
	
func measure_velocity_decay():
	#STRENGTH:50.0
	#-56.0
	#250.0
	#50.4178352355957
	#201.3793640136723
	
	# STRENGTH:100.0
	#-56.0
	#500.0
	#50.5656967163086
	#471.693389892578

	if ball_num == 0 and printed_cnt == 0 and linear_velocity.length() > 0.05:
		print(global_position.x)
		print(linear_velocity.x)
		printed_cnt += 1
	if ball_num == 0 and printed_cnt == 1 and global_position.x > 50 and linear_velocity.length() > 0.01:
		print(global_position.x)
		print(linear_velocity.x)
		printed_cnt += 1
	

func _physics_process(delta):
	#measure_velocity_decay()
	
	var friction_accel := 2

	linear_velocity = linear_velocity.move_toward(Vector3.ZERO, friction_accel * delta)
	angular_velocity = angular_velocity.move_toward(Vector3.ZERO, friction_accel * delta)
	#angular_velocity = -linear_velocity.cross(Vector3.UP) / Constants.BALL_RADIUS

	if linear_velocity.length() < 0.05:
		linear_velocity = Vector3.ZERO

	if angular_velocity.length() < 0.1:
		angular_velocity = Vector3.ZERO

func is_cue_ball():
	return ball_num == 0	

func is_solid():
	return 0 < ball_num and ball_num < 8
	
func is_eight_ball():
	return ball_num == 8
	
func is_stripe():
	return ball_num > 8

func _on_body_entered(body: Node) -> void:
	#print("Collision with cue ball: " + body.name)
	if first_hit_ball_num <= 0 and body.name.contains("Ball"):
		first_hit_ball_num = body.ball_num
		first_hit_ball_changed.emit()
	
