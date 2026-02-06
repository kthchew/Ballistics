extends Node3D

signal new_turn

@onready var tick_label: Label = $"Control/TickLabel"

var balls: Array[RigidBody3D] = []
var speed_threshold: float = 0.25
var angular_speed_threshold: float = 0.25
# physics defaults to 60 ticks per second
var static_ticks_threshold = 60
var cur_static_ticks = 0
var player_ind: int = 0
var scores = [0, 0]
var playing: bool = true

const ball_scene = preload("res://ball.tscn")

func _ready() -> void:
	playing = true
	var cue_ball: RigidBody3D = $CueBall
	balls.append(cue_ball)
	init_break_triangle(56, 0)
	
			
func init_break_triangle(x_shift: float, z_shift: float):
	var ball_ind: int = 0
	var ball_radius: float = 2.85
	var spacing: float = 1.05
	
	var colors = [
		[255, 215, 4], 
		[0, 0, 254], 
		[255, 0, 0], 
		[128, 0, 129], 
		[254, 165, 0], 
		[35, 139, 35], 
		[128, 0, 1],
		[0, 0, 0],
	]
	
	var ball_nums = range(1, 16)
	ball_nums.shuffle()
	print(ball_nums)
	
	for i in range(5):
		for j in range(i + 1):
			print(str(i) + " "  + str(j))
			var ball_node: Node = ball_scene.instantiate()
			var ball_num: int = ball_nums[ball_ind]
			ball_node.name = "Ball%s" % ball_num
			var x: float = x_shift + spacing * i * ball_radius * sqrt(3)
			var y: float = ball_radius
			var z: float = z_shift + (-i + 2 * j) * ball_radius * spacing
			ball_node.position = Vector3(x, y, z)
			
			var mesh = ball_node.get_node("MeshInstance3D")
			var material: Material = StandardMaterial3D.new()
			
			var color_num = ball_num
			if color_num > 8:
				color_num -= 8
			var color = colors[color_num - 1]
			print(ball_num)
			print(color_num)
			print(color)
			material.albedo_color = Color(color[0] / 255.0, color[1] / 255.0, color[2] / 255.0)
			#material.albedo_texture = null
			
			mesh.set_surface_override_material(0, material)
			
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

func delete_fallen_balls() -> void:
	var balls_to_erase: Array[RigidBody3D] = []
	for ball in balls:
		if ball.position.y < -10:
			print(ball.name + " fell")
			balls_to_erase.append(ball)
	
	for ball in balls_to_erase:
		if ball.name == "CueBall":
			ball.position = Vector3(0, 10, 0)
			ball.linear_velocity = Vector3(0, 0, 0)
			ball.angular_velocity = Vector3(0, 0, 0)
			continue
			
		scores[player_ind] += 1
		balls.erase(ball)
		ball.queue_free()

func _physics_process(delta: float) -> void:
	delete_fallen_balls()
	if check_all_not_moving():
		cur_static_ticks += 1
	else:
		playing = false
		cur_static_ticks = 0
	
	var label_txt = "Static Ticks: " + str(cur_static_ticks)
	label_txt += "\nCurrent Player: " + str(player_ind + 1)
	label_txt += "\nPlayer 1 Score: " + str(scores[0])
	label_txt += "\nPlayer 2 Score: " + str(scores[1])
	tick_label.text = label_txt
	
	if !playing and cur_static_ticks == static_ticks_threshold:
		player_ind = 1 - player_ind
		new_turn.emit()
		playing = true
	
