extends Node3D

@export var max_pullback: float = 10.0
@export var start_offset: float = 2.85

var angle: float = 0.0
var aim_direction: Vector3 = Vector3.FORWARD
var cue_ball_position: Vector3
var pull_amount: float = 0.0
var striking := false

func set_angle(a: float) -> void:
	angle = a
	aim_direction = Vector3(cos(a), 0, sin(a)).normalized()

	look_at(cue_ball_position, Vector3.UP)
	_update_absolute_position()

func set_force_strength(strength: float) -> void:
	strength = clamp(strength, 0.0, 1.0)
	pull_amount = max_pullback * strength
	_update_absolute_position()

func update_position(ball_pos: Vector3) -> void:
	cue_ball_position = ball_pos
	_update_absolute_position()

func _update_absolute_position():
	if striking:
		return

	if aim_direction == Vector3.ZERO:
		return

	var R = 2.85
	var S = start_offset
	var P = pull_amount

	global_position = cue_ball_position - aim_direction * (R + S + P)
