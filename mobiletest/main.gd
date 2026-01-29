extends Node3D

@onready var ball1 = $Ball1
@onready var ball2 = $Ball2
@onready var joy_left = $UI/JoystickLeft
@onready var joy_right = $UI/JoystickRight

var force_strength := 20.0

func _physics_process(delta):
	# Convert joystick 2D to world 3D (XZ plane)
	var dir1 = Vector3(joy_left.output.x, 0, joy_left.output.y)
	var dir2 = Vector3(joy_right.output.x, 0, joy_right.output.y)

	ball1.apply_central_force(dir1 * force_strength)
	ball2.apply_central_force(dir2 * force_strength)
