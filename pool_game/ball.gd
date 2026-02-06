extends RigidBody3D

var last_vel: Vector3 = Vector3(0, 0, 0)
var ball_num: int = 0

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

func _physics_process(delta):
	#if last_vel.length() > 0.2 and linear_velocity.length() < 0.2:
		#linear_damp = 0.5
	#if ball_num == 0:
		#print(linear_velocity)
		#print(global_position)
	last_vel = linear_velocity
	
