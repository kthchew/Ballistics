extends Node3D

signal new_turn

@onready var tick_label: Label = $"Control/TickLabel"

var balls: Array[RigidBody3D] = []
var speed_threshold: float = 0.1
var angular_speed_threshold: float = 0.1
var static_ticks_threshold = 60
var cur_static_ticks = 0


func _ready() -> void:
	var cue_ball: RigidBody3D = $CueBall
	balls.append(cue_ball)
	#cue_ball.apply_central_impulse(Vector3(30, 0, 0))
	#cue_ball.apply_torque_impulse(Vector3(0, 1000, 0))
	
	for i in range(1):
		var ball_path: String = "Ball%s" % i
		var ball: RigidBody3D = get_node(ball_path)
		balls.append(ball)
	
	
func all_not_moving() -> bool:
	for ball in balls:
		if ball.get_linear_velocity().length() > speed_threshold \
		or ball.get_angular_velocity().length() > angular_speed_threshold:
			return false
	return true


func _physics_process(delta: float) -> void:
	if all_not_moving():
		cur_static_ticks += 1
	else:
		cur_static_ticks = 0
	
	tick_label.text = "Static Ticks: " + str(cur_static_ticks)
	
	if cur_static_ticks == static_ticks_threshold:
		new_turn.emit()
	
