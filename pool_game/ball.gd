extends RigidBody3D

const BALL_RADIUS = 2.85

var ball_num: int = 0
var first_hit_ball_num: int = -1
var teleport_requested: bool = false
var teleport_pos: Vector3 = Vector3.ZERO
var potted: bool = false

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
	rotation = Vector3(0, 0, 0)
	freeze = true
	# position set manually + teleport are both needed for some reason
	position = Vector3(125, 0, -50 + 2 * BALL_RADIUS * ball_num)
	teleport(Vector3(125, 0, -50 + 2 * BALL_RADIUS * ball_num))
	potted = true

func _physics_process(delta):
	var friction_accel := 2

	linear_velocity = linear_velocity.move_toward(Vector3.ZERO, friction_accel * delta)
	angular_velocity = angular_velocity.move_toward(Vector3.ZERO, friction_accel * delta)

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
	print("Collision with cue ball: " + body.name)
	if first_hit_ball_num <= 0 and body.name.contains("Ball"):
		first_hit_ball_num = body.ball_num
	
