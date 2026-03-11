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

		preview.global_position = hit


func _on_place_button_pressed() -> void:
	if preview.occupied > 0:
		print("occupied too big")
		return
	if preview is RigidBody3D:
		preview.freeze = false
	preview.collision_layer = 2
	preview.set_collision_mask(1)
	preview.set_collision_mask(2)
	var parent = get_parent()
	parent.visible = false
	parent.get_parent().get_node("UI").visible = true
	preview = null
