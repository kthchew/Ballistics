extends Node3D

signal new_turn

@onready var tick_label: Label = $"Control/TickLabel"
@onready var cue_ball: RigidBody3D = $CueBall

var balls: Array[RigidBody3D] = []
var speed_threshold: float = 0.25
var angular_speed_threshold: float = 0.25
# physics defaults to 60 ticks per second
var static_ticks_threshold = 60
var cur_static_ticks = 0
var player_ind: int = 1
var scores = [0, 0]
var playing: bool = true
var cue_ball_potted: bool = false

const ball_scene = preload("res://ball.tscn")

func _ready() -> void:
	playing = true
	balls.append(cue_ball)
	init_break_triangle(56, 0)
	

func color_ball(ball_node: RigidBody3D, ball_num, colors) -> void:
	var mesh = ball_node.get_node("MeshInstance3D")
	var material: Material = StandardMaterial3D.new()
	
	ball_node.rotation = Vector3(0, 0, PI / 2)
	
	if ball_num > 8:
		var gradient: Gradient = Gradient.new()
		gradient.remove_point(0)
		gradient.remove_point(0)
		gradient.add_point(0.4, Color(1, 1, 1))
		gradient.add_point(0.4, Color(0, 0, 0))
		gradient.add_point(0.6, Color(0, 0, 0))
		gradient.add_point(0.6, Color(1, 1, 1))
		var gradient_texture: GradientTexture2D = GradientTexture2D.new()
		gradient_texture.fill_from = Vector2(0.5, 0)
		gradient_texture.fill_to = Vector2(0.5, 1)
		gradient_texture.gradient = gradient
		material.albedo_texture = gradient_texture
	
	var color_num = ball_num
	if color_num > 8:
		color_num -= 8
	var color = colors[color_num - 1]
	material.albedo_color = Color(color[0] / 255.0, color[1] / 255.0, color[2] / 255.0)
	
	mesh.set_surface_override_material(0, material)
			
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
	ball_nums.erase(8)
	ball_nums.shuffle()
	ball_nums.insert(4, 8)
	
	for i in range(5):
		for j in range(i + 1):
			var ball_node: Node = ball_scene.instantiate()
			var ball_num: int = ball_nums[ball_ind]
			ball_node.name = "Ball%s" % ball_num
			ball_node.ball_num = ball_num
			var x: float = x_shift + spacing * i * ball_radius * sqrt(3)
			var y: float = ball_radius
			var z: float = z_shift + (-i + 2 * j) * ball_radius * spacing
			ball_node.position = Vector3(x, y, z)
			
			color_ball(ball_node, ball_num, colors)
			
			balls.append(ball_node)
			add_child(ball_node)
			
			ball_ind += 1
	
	
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
		if ball.ball_num == 0:
			ball.position = Vector3(-2000, 0, 0)
			ball.linear_velocity = Vector3(0, 0, 0)
			ball.angular_velocity = Vector3(0, 0, 0)
			ball.rotation = Vector3(0, 0, 0)
			ball.freeze = true
			cue_ball_potted = true
			cue_ball.hide()
			continue
		elif ball.ball_num > 8:
			scores[1] += 1
		elif ball.ball_num < 8:
			scores[0] += 1
		if ball.ball_num == 8:
			if scores[player_ind] == 7:
				scores[player_ind] += 1
			else:
				scores[player_ind] = -1000
			
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
		if cue_ball_potted:
			cue_ball_potted = false
			cue_ball.freeze = false
			cue_ball.show()
			cue_ball.position = Vector3(-56.0, 2.85, 0)
		else:
			player_ind = 1 - player_ind
			new_turn.emit()
			playing = true
	
