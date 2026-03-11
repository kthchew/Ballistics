extends Control

@export var table_plane_y := 0.0
var preview :Node3D= null
var dragging := false

func _on_power_2_pressed() -> void:
	print("pressed")
	self.visible = true
	var block_scene: PackedScene = preload("res://block.tscn")
	start_placement(block_scene)

func start_placement(scene: PackedScene):
	preview = scene.instantiate()

	if preview is RigidBody3D:
		preview.freeze = true

	preview.visible = true
	get_node("/root/Main/PreviewContainer").add_child(preview)

func cancel_placement():
	if preview:
		preview.queue_free()
		preview = null
	
func _gui_input(event):
	if not preview:
		return

	if event is InputEventScreenTouch:
		dragging = event.pressed

	if event is InputEventScreenDrag and dragging:
		var pos = event.position
		var cam = get_viewport().get_camera_3d()
		var from = cam.project_ray_origin(pos)
		var dir = cam.project_ray_normal(pos)

		# Ray-plane intersection with table plane
		var t = (table_plane_y - from.y) / dir.y
		var hit = from + dir * t

		var shape = preview.get_node("CollisionShape3D").shape
		var half_height = shape.size.y * 0.5
		preview.global_position = hit + Vector3(0, half_height, 0)


func _on_place_button_pressed() -> void:
	if preview.occupied > 0:
		print("occupied too big")
		return
	if preview is RigidBody3D:
		preview.freeze = false
	preview.set_collision_layer_value(3, true)
	preview.set_collision_mask_value(2, true)
	preview.set_collision_mask_value(3, true)
	var parent = get_parent()
	parent.visible = false
	parent.get_parent().get_node("UI").visible = true
	preview = null
	
var rotating_left := false
var rotating_right := false

func _process(delta):
	if preview:
		if rotating_left:
			preview.rotate_y(deg_to_rad(1))
		if rotating_right:
			preview.rotate_y(deg_to_rad(-1))
			
func _on_rotate_left_button_down():
	rotating_left = true

func _on_rotate_left_button_up():
	rotating_left = false

func _on_rotate_right_button_down():
	rotating_right = true

func _on_rotate_right_button_up():
	rotating_right = false
