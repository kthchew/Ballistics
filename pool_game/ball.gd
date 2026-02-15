extends RigidBody3D

var last_vel: Vector3 = Vector3(0, 0, 0)
var ball_num: int = 0

@onready var ai_controller = $"../AIController3D"

'''
func _input(event):
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.is_action("move_right"):
			apply_central_impulse(Vector3(50, 0, 0))
		elif event.is_action("move_left"):
			apply_central_impulse(Vector3(-50, 0, 0))
		if event.is_action("move_up"):
			apply_central_impulse(Vector3(0, 0, -50))
		elif event.is_action("move_down"):
			apply_central_impulse(Vector3(0, 0, 50))
'''

func reset():
	position = Vector3(-56.0, 2.85, 0)
	linear_velocity = Vector3(0, 0, 0)
	angular_velocity = Vector3(0, 0, 0)	
	freeze = false
	show()

func _physics_process(delta):
	#if last_vel.length() > 0.2 and linear_velocity.length() < 0.2:
		#linear_damp = 0.5
	#if ball_num == 0:
		#print(linear_velocity)
		#print(global_position)
	var friction_accel := 2

	linear_velocity = linear_velocity.move_toward(Vector3.ZERO, friction_accel * delta)

	angular_velocity = angular_velocity.move_toward(Vector3.ZERO, friction_accel * delta)

	if linear_velocity.length() < 0.05:
		linear_velocity = Vector3.ZERO

	if angular_velocity.length() < 0.1:
		angular_velocity = Vector3.ZERO


func _on_body_entered(body: Node) -> void:
	if body.name.contains("Ball") and body.ball_num < 8:
		ai_controller.reward += 0.1
