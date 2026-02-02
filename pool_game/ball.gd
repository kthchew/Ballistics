extends RigidBody3D

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
	pass
	
