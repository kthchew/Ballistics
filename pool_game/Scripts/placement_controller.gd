extends Control

@export var table_plane_y := 0.0
var preview: Node3D = null
var illegalMat: Material
var legalMat: Material
var dragging := false
var owner_peer_id := -1

var game_root: Node = null
var preview_container: Node = null
var power_name = null

const power_scenes: Dictionary[String, Resource] = {
	"block": preload("res://Scenes/Powers/block.tscn"),
	"tnt": preload("res://Scenes/Powers/tnt.tscn"),
	"tungsten": preload("res://Scenes/Powers/tungsten.tscn")
}

func _ready():
	game_root = get_node("../..")
	preview_container = game_root.get_node("PreviewContainer")

@rpc("authority", "call_local")
func set_cashout_owner(cashout_owner_peer_id: int):
	self.owner_peer_id = cashout_owner_peer_id

func _on_power_1_pressed():
	if multiplayer.get_unique_id() != owner_peer_id:
		return
	var button = $"../Panel/HBoxContainer/Power1"
	var selected_power = button.get_meta("power_name")
	if selected_power == null:
		return
	self.visible = true
	power_name = selected_power
	start_placement(power_name)

func _on_power_2_pressed():
	if multiplayer.get_unique_id() != owner_peer_id:
		return
	var button = $"../Panel/HBoxContainer/Power2"
	var selected_power = button.get_meta("power_name")
	if selected_power == null:
		return
	self.visible = true
	power_name = selected_power
	start_placement(power_name)

func _on_power_3_pressed():
	if multiplayer.get_unique_id() != owner_peer_id:
		return
	var button = $"../Panel/HBoxContainer/Power3"
	var selected_power = button.get_meta("power_name")
	if selected_power == null:
		return
	self.visible = true
	power_name = selected_power
	start_placement(power_name)


func start_placement(power_key: String):
	var scene: Resource = power_scenes[power_key]
	preview = scene.instantiate()
	preview.visible = true
	preview_container.add_child(preview)
	illegalMat = preview.get_node_or_null("MeshInstance3D").get_active_material(0).duplicate()
	illegalMat.albedo_color = Color(1, 0.3, 0.3)
	illegalMat.emission_enabled = true
	illegalMat.emission = Color(1, 0, 0)
	legalMat = preview.get_node_or_null("MeshInstance3D").get_active_material(0)

	rpc_spawn_preview.rpc(power_key)

func set_preview_illegal(illegal: bool):
	var mesh = preview.get_node_or_null("MeshInstance3D")
	if not mesh:
		return

	if illegal:
		mesh.set_surface_override_material(0, illegalMat)
	else:
		mesh.set_surface_override_material(0, legalMat)

@rpc("any_peer", "call_remote")
func rpc_spawn_preview(power_key: String):
	if multiplayer.get_unique_id() == owner_peer_id:
		return
	var scene = power_scenes[power_key]
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
	var scene = power_scenes[pName]
	var obj = scene.instantiate()

	preview_container.add_child(obj)
	obj.global_position = pos
	obj.global_rotation = rot

	if obj is RigidBody3D:
		obj.freeze = false

	if power_type == "Object":
		obj.collision_layer = (1 << 2) | (1 << 3)
		obj.collision_mask = (1 << 0) | (1 << 2) | (1 << 3)
		game_root.active_power_objects += 1

	return obj

func save_object_powers() -> Array:
	var object_states: Array = []
	if not preview_container:
		return object_states

	for child in preview_container.get_children():
		if child == preview:
			continue
		if not ("power_type" in child) or child.power_type != "Object":
			continue
		if not ("power_scene_name" in child):
			continue

		object_states.append({
			"type": String(child.power_scene_name),
			"pos_x": child.global_position.x,
			"pos_y": child.global_position.y,
			"pos_z": child.global_position.z,
			"rot_x": child.global_rotation.x,
			"rot_y": child.global_rotation.y,
			"rot_z": child.global_rotation.z,
		})

	return object_states

func _clear_object_powers() -> void:
	if not preview_container:
		return

	for child in preview_container.get_children():
		if child == preview:
			continue
		if ("power_type" in child) and child.power_type == "Object":
			child.queue_free()

func load_object_powers(saved_object_powers: Array) -> void:
	_clear_object_powers()

	if game_root:
		game_root.active_power_objects = 0

	for state in saved_object_powers:
		if not (state is Dictionary):
			continue

		var saved_power_name := String(state.get("type", ""))
		if saved_power_name == "" or not power_scenes.has(saved_power_name):
			continue

		var pos := Vector3(
			float(state.get("pos_x", 0.0)),
			float(state.get("pos_y", 0.0)),
			float(state.get("pos_z", 0.0))
		)
		var rot := Vector3(
			float(state.get("rot_x", 0.0)),
			float(state.get("rot_y", 0.0)),
			float(state.get("rot_z", 0.0))
		)

		_spawn_power_local("Object", saved_power_name, pos, rot)
		if multiplayer.is_server():
			rpc("rpc_spawn_power", "Object", saved_power_name, pos, rot)

@rpc("any_peer", "reliable")
func rpc_spawn_power(power_type: String, pName: String, pos: Vector3, rot: Vector3):
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

	if "modifiers" in target:
		target.modifiers.append(pName)

	if pName == "tnt":
		var low = target.name.to_lower()
		if not low.contains("ball") and not low.contains("table"):
			target.queue_free()
			game_root.active_power_objects = max(0, game_root.active_power_objects - 1)

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
		if not game_root or not game_root.server_try_consume_power_purchase(sender, pName):
			return
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
			if not game_root or not game_root.server_try_consume_power_purchase(sender, pName):
				return
			_apply_modifier(pName, target.get_path())
			rpc("rpc_apply_modifier", pName, target.get_path())
		else:
			return

	finish_placement.rpc_id(sender)
	if game_root and game_root.has_method("persist_game_state"):
		game_root.persist_game_state()


@rpc("any_peer", "call_local")
func finish_placement():
	self.visible = false
	if preview:
		preview.queue_free()
		preview = null
	if game_root and game_root.has_method("update_powerup_shop"):
		game_root.update_powerup_shop()
	if game_root and game_root.has_node("pUI"):
		var p_ui = game_root.get_node("pUI")
		p_ui.visible = true
		if p_ui.has_node("Panel"):
			p_ui.get_node("Panel").visible = true
	power_name = null
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
	if game_root.has_node("pUI/placementController"):
		game_root.get_node("pUI/placementController").visible = false
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

		set_preview_illegal(not preview.canPlace())

func _on_rotate_left_button_down(): rotating_left = true
func _on_rotate_left_button_up(): rotating_left = false
func _on_rotate_right_button_down(): rotating_right = true
func _on_rotate_right_button_up(): rotating_right = false
