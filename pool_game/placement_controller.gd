extends Control

@export var table_plane_y := 0.0
var preview: Node3D = null
var dragging := false
var owner_peer_id := -1

var game_root: Node = null
var preview_container: Node = null
var power_name = null

func _ready():
	game_root = get_node("../..")
	preview_container = game_root.get_node("PreviewContainer")

@rpc("authority", "call_local")
func set_cashout_owner(owner_peer_id: int):
	self.owner_peer_id = owner_peer_id

func _on_power_1_pressed():
	if multiplayer.get_unique_id() != owner_peer_id:
		return
	self.visible = true
	power_name = $"../Panel/HBoxContainer/Power1".text
	start_placement(load("res://Powers/%s.tscn" % power_name))

func _on_power_2_pressed():
	if multiplayer.get_unique_id() != owner_peer_id:
		return
	self.visible = true
	power_name = $"../Panel/HBoxContainer/Power2".text
	start_placement(load("res://Powers/%s.tscn" % power_name))

func _on_power_3_pressed():
	if multiplayer.get_unique_id() != owner_peer_id:
		return
	self.visible = true
	power_name = $"../Panel/HBoxContainer/Power3".text
	start_placement(load("res://Powers/%s.tscn" % power_name))


func start_placement(scene: PackedScene):
	preview = scene.instantiate()
	preview.visible = true
	preview_container.add_child(preview)

	rpc("rpc_spawn_preview", scene.resource_path)

@rpc("any_peer", "call_remote")
func rpc_spawn_preview(scene_path: String):
	if multiplayer.get_unique_id() == owner_peer_id:
		return
	var scene = load(scene_path)
	preview = scene.instantiate()
	preview.visible = true
	preview_container.add_child(preview)

func cancel_placement():
	if preview:
		preview.queue_free()
		preview = null

func _gui_input(event):
	if multiplayer.get_unique_id() != owner_peer_id:
		return
	if not preview:
		return

	if event is InputEventScreenTouch:
		dragging = event.pressed

	if event is InputEventScreenDrag and dragging:
		var pos = event.position
		var cam = get_viewport().get_camera_3d()
		var from = cam.project_ray_origin(pos)
		var dir = cam.project_ray_normal(pos)

		var t = (table_plane_y - from.y) / dir.y
		var hit = from + dir * t

		var shape = preview.get_node("CollisionShape3D").shape
		var half_height = shape.size.y * 0.5
		preview.global_position = hit + Vector3(0, half_height, 0)

		rpc("rpc_update_preview", preview.global_position, preview.global_rotation)


@rpc("any_peer", "call_remote", "unreliable")
func rpc_update_preview(pos: Vector3, rot: Vector3):
	if multiplayer.get_unique_id() == owner_peer_id:
		return
	if preview:
		preview.global_position = pos
		preview.global_rotation = rot

func _on_place_button_pressed():
	if multiplayer.get_unique_id() != owner_peer_id:
		return
	if not preview:
		return

	var target_path := ""
	if preview.power_type == "Modifier":
		var area = preview.get_node_or_null("Area3D")
		if area:
			var overlaps = area.get_overlapping_areas()
			if overlaps.size() == 1:
				target_path = overlaps[0].get_parent().get_path()

	request_place_power.rpc(
		preview.power_type,
		preview.global_position,
		preview.global_rotation,
		preview.occupied,
		preview.power_scene_name,
		target_path
	)


func _spawn_power_local(power_type: String, pName: String, pos: Vector3, rot: Vector3) -> Node:
	var scene = load("res://Powers/%s.tscn" % pName)
	var obj = scene.instantiate()

	preview_container.add_child(obj)
	obj.global_position = pos
	obj.global_rotation = rot

	if obj is RigidBody3D:
		obj.freeze = false

	if power_type == "Object":
		obj.collision_layer = 3
		obj.collision_mask = 3

	if multiplayer.is_server() and power_type == "Object":
		game_root.objects += 1

	return obj

@rpc("any_peer", "reliable")
func rpc_spawn_power(power_type: String, pName: String, pos: Vector3, rot: Vector3):
	if multiplayer.is_server():
		return
	_spawn_power_local(power_type, pName, pos, rot)

func _get_node_by_global_path(path: String) -> Node:
	if path == "":
		return null
	var root = get_tree().get_root()
	return root.get_node_or_null(path)

func _apply_modifier(pName: String, modified_path: String) -> void:
	var target = _get_node_by_global_path(modified_path)
	if not target:
		return

	if pName == "tnt":
		var low = target.name.to_lower()
		if not low.contains("ball") and not low.contains("table"):
			target.queue_free()
			if multiplayer.is_server():
				game_root.objects = max(0, game_root.objects - 1)

	elif pName == "tungsten":
		if target is RigidBody3D:
			target.mass = 11
			var mesh = target.get_node_or_null("MeshInstance3D")
			if mesh:
				var mat = mesh.get_active_material(0)
				if mat:
					mat = mat.duplicate()
					mat.albedo_color = Color.GRAY
					mat.metallic = 1.0
					mat.roughness = 0.1
					mesh.set_surface_override_material(0, mat)

@rpc("any_peer", "reliable")
func rpc_apply_modifier(pName: String, modified_path: String) -> void:
	if multiplayer.is_server():
		return
	_apply_modifier(pName, modified_path)

@rpc("any_peer", "reliable")
func request_place_power(power_type: String, pos: Vector3, rot: Vector3, occupied: int, pName: String, target_path: String = ""):
	if not multiplayer.is_server():
		return

	var sender = multiplayer.get_remote_sender_id()
	if sender != owner_peer_id:
		return

	if power_type == "Object" and occupied > 0:
		return
	if power_type == "Modifier" and occupied != 1:
		return

	if power_type == "Object":
		_spawn_power_local(power_type, pName, pos, rot)
		rpc("rpc_spawn_power", power_type, pName, pos, rot)

	else:
		var target = _get_node_by_global_path(target_path)
		if not target:
			var obj = _spawn_power_local(power_type, pName, pos, rot)
			var area = obj.get_node_or_null("Area3D")
			if area and area.get_overlapping_areas().size() == 1:
				target = area.get_overlapping_areas()[0].get_parent()
			obj.queue_free()

		if target:
			_apply_modifier(pName, target.get_path())
			rpc("rpc_apply_modifier", pName, target.get_path())

	game_root.cashout = false
	game_root.end_round()

	finish_placement.rpc_id(sender)


@rpc("any_peer", "call_local")
func finish_placement():
	self.visible = false
	if preview:
		preview.queue_free()
		preview = null
	rpc("rpc_clear_preview")
	rpc("rpc_exit_powerup_ui")


@rpc("any_peer", "call_remote")
func rpc_clear_preview():
	if preview:
		preview.queue_free()
		preview = null

@rpc("any_peer", "reliable")
func rpc_exit_powerup_ui():
	if not game_root:
		return
	if game_root.has_node("pUI"):
		game_root.get_node("pUI").visible = false
	if game_root.has_node("UI"):
		game_root.get_node("UI").visible = true
	if game_root.has_method("set_visibility"):
		game_root.set_visibility()

var rotating_left := false
var rotating_right := false

func _process(delta):
	if multiplayer.get_unique_id() != owner_peer_id:
		return
	if preview:
		var rotated := false

		if rotating_left:
			preview.rotate_y(deg_to_rad(1))
			rotated = true

		if rotating_right:
			preview.rotate_y(deg_to_rad(-1))
			rotated = true

		if rotated:
			rpc("rpc_update_preview", preview.global_position, preview.global_rotation)


func _on_rotate_left_button_down(): rotating_left = true
func _on_rotate_left_button_up(): rotating_left = false
func _on_rotate_right_button_down(): rotating_right = true
func _on_rotate_right_button_up(): rotating_right = false
