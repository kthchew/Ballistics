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
	aim_line.visible = false
	$UI/AimInputRegion.aim_changed.connect(_on_aim_changed)
	slider.value_changed.connect(_on_force_changed)
	fire_button.pressed.connect(_on_fire_pressed)

func _on_aim_changed(touch_pos: Vector2):
	if !playing:
		return

	var ball_screen_pos = $CameraPivot/Camera3D.unproject_position(cue_ball.global_position)
	var dir = ball_screen_pos - touch_pos

	if dir.length() < 20:
		return

	if not has_aimed:
		has_aimed = true
		aim_line.visible = true

	var dir_norm = dir.normalized()

	var ball_center_3d = cue_ball.global_position
	var ball_edge_3d = ball_center_3d + Vector3(5, 0, 0)
	var center_screen = $CameraPivot/Camera3D.unproject_position(ball_center_3d)
	var edge_screen = $CameraPivot/Camera3D.unproject_position(ball_edge_3d)
	var ball_radius_px = (edge_screen - center_screen).length()
	var cue_pos = ball_screen_pos - dir_norm * ball_radius_px
	aim_line.global_position = cue_pos

	aim_line.set_angle(dir.angle())

func _on_force_changed(value):
	var normalized = value / $UI/ForceSlider.max_value
	$UI/AimLine.set_force_strength(normalized)

func _on_fire_pressed():
	var strength = slider.value
	var angle = aim_line.angle

	var dir = Vector3(cos(angle), 0, sin(angle)).normalized()
	var force = dir * (strength * 5)

	var up = Vector3.UP
	if abs(dir.dot(up)) > 0.9:
		up = Vector3.FORWARD

	var right = dir.cross(up).normalized()
	var forward = right.cross(dir).normalized()

	var face_radius = 0.5
	var joy = aimer.output
	var offset_3d = right * (joy.x * face_radius) + forward * (-joy.y * face_radius)

	cue_ball.apply_impulse(force, offset_3d)

	has_aimed = false

	slider.value = 0
	aim_line.visible = false
	aim_line.set_force_strength(0.0)
	aimer._reset_knob()

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
	
	for i in range(5):
		for j in range(i + 1):
			print(str(i) + " "  + str(j))
			var ball_node: Node = ball_scene.instantiate()
			ball_node.name = "Ball%s" % ball_ind
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
	print(playing)
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
	
