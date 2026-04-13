class_name Ball extends RigidBody3D

signal first_hit_ball_changed

@onready var BallCollide: AudioStreamPlayer3D = $BallCollide
@onready var HoleSound: AudioStreamPlayer3D = $Hole
@onready var CueCollide: AudioStreamPlayer3D = $CueCollide

@export var ball_num: int = 0

var first_hit_ball_num: int = -1
var teleport_requested: bool = false
var teleport_pos: Vector3 = Vector3.ZERO
var potted: bool = false

var modifiers: Array[String] = []

func _ready() -> void:
	HoleSound.max_db = 80.0
	BallCollide.max_db = 80.0
	
func save() -> Dictionary:
	var save_dict: Dictionary[Variant, Variant] = {
		"ball_num": ball_num,
		"pos_x": position.x,
		"pos_y": position.y,
		"pos_z": position.z,
		"rot_x": rotation.x,
		"rot_y": rotation.y,
		"rot_z": rotation.z,
		"potted": potted,
		
		"modifiers": modifiers.duplicate(),
	}
	return save_dict

func teleport(pos: Vector3) -> void:
	teleport_requested = true
	teleport_pos = pos

func play_hole_sound():
	HoleSound.play(0.0)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if teleport_requested:
		teleport_requested = false
		var new_basis = Basis.from_euler(Vector3(PI / 2, 0, PI))
		var new_transform: Transform3D = Transform3D(new_basis)
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
	# print("Collision with cue ball: " + body.name)
	if self.is_cue_ball() and first_hit_ball_num <= 0 and body.name.contains("Ball"):
		first_hit_ball_num = body.ball_num
		first_hit_ball_changed.emit()

func _on_area_3d_area_entered(area: Area3D) -> void:
	var other := area.get_parent()
	if other is RigidBody3D:
		var rel_vel: float = (linear_velocity - other.linear_velocity).length()
		var max_velocity := 150.0
		var t: float = clamp(rel_vel / max_velocity, 0.0, 1.0)

		$BallCollide.volume_db = lerp(-25.0, 2.0, sqrt(t))
		$BallCollide.pitch_scale = lerp(0.85, 1.2, t)
		$BallCollide.play(0.0)
