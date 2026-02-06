extends Node3D

var has_aimed := false
signal new_turn

@onready var tick_label: Label = $"Control/TickLabel"
@onready var cue_ball: RigidBody3D = $CueBall
@onready var aim_line = $UI/AimLine
@onready var slider = $UI/ForceSlider
@onready var fire_button = $UI/FireButton
@onready var aimer = $UI/Aimer

var balls: Array[RigidBody3D] = []
var speed_threshold: float = 0.25
var angular_speed_threshold: float = 0.25
# physics defaults to 60 ticks per second
var static_ticks_threshold = 60
var cur_static_ticks = 0

const ball_scene = preload("res://ball.tscn")	

func _ready() -> void:
	playing = true
	balls.append(cue_ball)
	init_break_triangle(56, 0)
	aim_line.visible = false
	$UI/AimInputRegion.aim_changed.connect(_on_aim_changed)
	slider.value_changed.connect(_on_force_changed)
	fire_button.pressed.connect(_on_fire_pressed)

func _on_aim_changed(touch_pos: Vector2):
	var ball_screen_pos = $CameraPivot/Camera3D.unproject_position(cue_ball.global_position)
	var dir = touch_pos - ball_screen_pos

	if dir.length() < 20:
		return

	if not has_aimed:
		has_aimed = true
		aim_line.visible = true

	aim_line.set_angle(dir.angle())

func _on_force_changed(value):
	var normalized = value / $UI/ForceSlider.max_value
	$UI/AimLine.set_force_strength(normalized)

func _on_fire_pressed():
	var strength = slider.value
	var angle = aim_line.angle

	var dir = Vector3(cos(angle), 0, sin(angle)).normalized()
	var force = dir * (strength * 50)

	var up = Vector3.UP
	if abs(dir.dot(up)) > 0.9:
		up = Vector3.FORWARD

	var right = dir.cross(up).normalized()
	var forward = right.cross(dir).normalized()

	var face_radius = 0.5
	var joy = aimer.output
	var offset_3d = right * (joy.x * face_radius) + forward * (-joy.y * face_radius)

	var local_offset = offset_3d

	cue_ball.apply_impulse(force, local_offset)

	has_aimed = false
	aim_line.visible = false
	aimer._reset_knob()
		
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
		balls.erase(ball)
		ball.queue_free()

func _physics_process(delta: float) -> void:
	delete_fallen_balls()
	if check_all_not_moving():
		cur_static_ticks += 1
	else:
		cur_static_ticks = 0
	
	var label_txt = "Static Ticks: " + str(cur_static_ticks)
	label_txt += "\nCurrent Player: " + str(player_ind + 1)
	label_txt += "\nPlayer 1 Score: " + str(scores[0])
	label_txt += "\nPlayer 2 Score: " + str(scores[1])
	tick_label.text = label_txt
	
	if cur_static_ticks == static_ticks_threshold:
		new_turn.emit()
	
