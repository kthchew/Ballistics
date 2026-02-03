extends Node3D

signal new_turn

@onready var tick_label: Label = $"Control/TickLabel"

var balls: Array[RigidBody3D] = []
var speed_threshold: float = 0.25
var angular_speed_threshold: float = 0.25
# physics defaults to 60 ticks per second
var static_ticks_threshold = 60
var cur_static_ticks = 0

const ball_scene = preload("res://ball.tscn")

func _ready() -> void:
	var cue_ball: RigidBody3D = $CueBall
	balls.append(cue_ball)
	init_break_triangle(5, 0)
	
			
func init_break_triangle(x_shift: float, z_shift: float):
	var ball_ind: int = 0
	var ball_radius: float = 2.85
	var spacing: float = 1.05
	for i in range(5):
		for j in range(i + 1):
			print(str(i) + " "  + str(j))
			var ball_node: Node = ball_scene.instantiate()
			ball_node.name = "Ball%s" % i
			var x: float = x_shift + spacing * i * ball_radius * sqrt(3)
			var y: float = ball_radius
			var z: float = z_shift + (-i + 2 * j) * ball_radius * spacing
			ball_node.position = Vector3(x, y, z)
			
			balls.append(ball_node)
			add_child(ball_node)
			
			ball_ind += 1
	
	#print(($"Ball0".position - $"Ball1".position).length())
	
	
func check_all_not_moving() -> bool:
	for ball in balls:
		if ball.get_linear_velocity().length() > speed_threshold \
		or ball.get_angular_velocity().length() > angular_speed_threshold:
			return false
	return true


func _physics_process(delta: float) -> void:
	if check_all_not_moving():
		cur_static_ticks += 1
	else:
		cur_static_ticks = 0
	
	tick_label.text = "Static Ticks: " + str(cur_static_ticks)
	
	if cur_static_ticks == static_ticks_threshold:
		new_turn.emit()
	
