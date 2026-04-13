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
var selected_power_cost: int = 0

const power_scenes: Dictionary[String, Resource] = {
	"block": preload("res://Scenes/Powers/block.tscn"),
	"tnt": preload("res://Scenes/Powers/tnt.tscn"),
	"tungsten": preload("res://Scenes/Powers/tungsten.tscn"),
	"aerogel": preload("res://Scenes/Powers/aerogel.tscn"),
	"bumper": preload("res://Scenes/Powers/bumper.tscn"),
	"eraser": preload("res://Scenes/Powers/eraser.tscn"),
	"gluetrap": preload("res://Scenes/Powers/gluetrap.tscn")
}

const power_descriptions: Dictionary[String, String] = {
	"block": "Block places a barrier that balls cannot pass through.",
	"tnt": "TNT destroys a placed object.",
	"tungsten": "Tungsten makes a ball heavier so it deflects less.",
	"aerogel": "Aerogel makes a ball lighter so it reacts more to hits.",
	"bumper": "Bumper bounces balls off it harder.",
	"eraser": "Eraser removes the active modifier from a ball.",
	"gluetrap": "Glue Trap stops balls that roll through it."
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
	var selected_cost = int(button.get_meta("power_cost"))
	if selected_power == null:
		return
	if selected_cost <= 0:
		return
	self.visible = true
	power_name = selected_power
	selected_power_cost = selected_cost
	start_placement(power_name, selected_power_cost)

func _on_power_2_pressed():
	if multiplayer.get_unique_id() != owner_peer_id:
		return
	var button = $"../Panel/HBoxContainer/Power2"
	var selected_power = button.get_meta("power_name")
	var selected_cost = int(button.get_meta("power_cost"))
	if selected_power == null:
		return
	if selected_cost <= 0:
		return
	self.visible = true
	power_name = selected_power
	selected_power_cost = selected_cost
	start_placement(power_name, selected_power_cost)

func _on_power_3_pressed():
	if multiplayer.get_unique_id() != owner_peer_id:
		return
	var button = $"../Panel/HBoxContainer/Power3"
	var selected_power = button.get_meta("power_name")
	var selected_cost = int(button.get_meta("power_cost"))
	if selected_power == null:
		return
	if selected_cost <= 0:
		return
	self.visible = true
	power_name = selected_power
	selected_power_cost = selected_cost
	start_placement(power_name, selected_power_cost)


func start_placement(power_key: String, cost: int):
	selected_power_cost = cost
	var scene: Resource = power_scenes[power_key]
	preview = scene.instantiate()
	preview.visible = true
	preview_container.add_child(preview)
	if game_root and game_root.has_method("show_powerup_hint"):
		var desc = power_descriptions.get(power_key, "Place this power-up on the table.")
		game_root.show_powerup_hint(desc)

	var mesh = preview.get_node_or_null("MeshInstance3D")
	if mesh:
		var active_mat = mesh.get_active_material(0)
		if active_mat:
			illegalMat = active_mat.duplicate()
			illegalMat.albedo_color = Color(1, 0.3, 0.3)
			illegalMat.emission_enabled = true
			illegalMat.emission = Color(1, 0, 0)
		legalMat = active_mat

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
		var half_height = 0
		if shape is CylinderShape3D :
			half_height = shape.height * 0.5
		else:
			half_height = shape.size.y * 0.5
		var placement_offset_y := 0.0
		if power_name == "gluetrap":
			placement_offset_y = 5.0
		preview.global_position = hit + Vector3(0, half_height + placement_offset_y, 0)

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
		print("multiplayer.get_unique_id() != owner_peer_id")
		return
	if not preview:
		print("not preview")
		return

	if not preview.canPlace():
		print("preview cannot be placed here")
		return

	var power_cost = selected_power_cost
	if power_cost <= 0 and game_root:
		power_cost = int(game_root.power_shop_costs.get(power_name, 0))
	
	if power_cost <= 0:
		print("power_cost <= 0")
		return

	var target_path = ""
	if preview.power_type == "Modifier":
		target_path = preview.get_target()
		
	if multiplayer.is_server():
		request_place_power(
			preview.power_type,
			preview.global_position,
			preview.global_rotation,
			preview.power_scene_name,
			power_cost,
			target_path
		)
	else:
		request_place_power.rpc_id(
			1,
			preview.power_type,
			preview.global_position,
			preview.global_rotation,
			preview.power_scene_name,
			power_cost,
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

	if pName == "gluetrap" and obj.has_method("mark_placed"):
		obj.mark_placed()
	if pName == "gluetrap":
		obj.collision_layer = Constants.GLUE_TRAP_LAYER
		obj.collision_mask = (1 << 0) | Constants.SHAPECAST_LAYER | Constants.GLUE_TRAP_LAYER
	elif power_type == "Object":
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
	
func remove_all_placed_powers():
	if not preview_container:
		return

	for child in preview_container.get_children():
		child.queue_free()

func _get_node_by_global_path(path: String) -> Node:
	if path == "":
		return null
	var root = get_tree().get_root()
	var absolute_node = root.get_node_or_null(path)
	if absolute_node:
		return absolute_node
	if game_root:
		return game_root.get_node_or_null(path)
	return null

func _find_object_power_near(world_pos: Vector3, max_distance: float = 8.0) -> Node:
	if not preview_container:
		return null

	var closest: Node = null
	var closest_distance := max_distance
	for child in preview_container.get_children():
		if str(child.get("power_type")) != "Object":
			continue
		var distance = child.global_position.distance_to(world_pos)
		if distance < closest_distance:
			closest_distance = distance
			closest = child
	return closest

func _apply_modifier(pName: String, modified_path: String, target_pos: Vector3 = Vector3.ZERO) -> void:
	var target = _get_node_by_global_path(modified_path)
	if not target and pName == "tnt":
		target = _find_object_power_near(target_pos)
	if not target:
		return

	var scene: PackedScene = power_scenes.get(pName)
	if not scene:
		return

	var power_instance = scene.instantiate()
	preview_container.add_child(power_instance)

	if power_instance.has_method("apply_to"):
		power_instance.apply_to(target)

	power_instance.visible = false

@rpc("any_peer", "reliable")
func rpc_apply_modifier(pName: String, modified_path: String, target_pos: Vector3 = Vector3.ZERO) -> void:
	_apply_modifier(pName, modified_path, target_pos)

@rpc("any_peer", "reliable")
func request_place_power(power_type: String, pos: Vector3, rot: Vector3, pName: String, cost: int, target_path: String = ""):
	if not multiplayer.is_server():
		return
	
	var sender = multiplayer.get_remote_sender_id()
	if sender != owner_peer_id:
		print("sender != owner_peer_id")
		return

	var scene: PackedScene = power_scenes.get(pName)
	if not scene:
		print("not scene")
		return
	var power_instance = scene.instantiate()
	
	preview_container.add_child(power_instance)
	power_instance.global_position = pos
	power_instance.global_rotation = rot
	power_instance.force_update_transform()
	var probe_area = power_instance.get_node_or_null("Area3D")
	if probe_area:
		probe_area.force_update_transform()
	
	# Wait for physics to process collision detection for modifiers
	if power_type == "Modifier":
		await get_tree().physics_frame
		await get_tree().physics_frame

	var resolved_target_path := target_path
	if power_type == "Modifier" and (resolved_target_path == "" or _get_node_by_global_path(resolved_target_path) == null):
		if power_instance.has_method("get_target"):
			resolved_target_path = power_instance.get_target()
		if (resolved_target_path == "" or _get_node_by_global_path(resolved_target_path) == null) and power_instance.has_method("get_target"):
			await get_tree().physics_frame
			resolved_target_path = power_instance.get_target()
	
	var placement_valid = power_instance.canPlace()
	if not placement_valid and power_type == "Modifier" and target_path != "":
		# Fallback for occasional client/server overlap timing mismatch.
		placement_valid = _get_node_by_global_path(resolved_target_path) != null

	if not placement_valid:
		print("not power_instance.canPlace()")
		power_instance.queue_free()
		return

	if power_type == "Modifier" and _get_node_by_global_path(resolved_target_path) == null:
		print("modifier target missing on server")
		power_instance.queue_free()
		return

	if not game_root or not game_root.try_purchase_power_for_peer(sender, pName, cost):
		print("purchase rejected for power placement")
		power_instance.queue_free()
		return

	if power_type == "Object":
		power_instance.queue_free()
		_spawn_power_local(power_type, pName, pos, rot)
		rpc("rpc_spawn_power", power_type, pName, pos, rot)

	else:
		var target = _get_node_by_global_path(resolved_target_path)

		if target:
			var target_path_for_rpc = str(game_root.get_path_to(target)) if game_root else str(target.get_path())
			_apply_modifier(pName, target_path_for_rpc, target.global_position)
			rpc("rpc_apply_modifier", pName, target_path_for_rpc, target.global_position)
		else:
			print("modifier apply skipped: target not found")
		power_instance.queue_free()
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
	selected_power_cost = 0
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
			preview.rotate_y(deg_to_rad(2))
			rotated = true

		if rotating_right:
			preview.rotate_y(deg_to_rad(-2))
			rotated = true

		if rotated:
			rpc("rpc_update_preview", preview.global_position, preview.global_rotation)

		set_preview_illegal(not preview.canPlace())

func _on_rotate_left_button_down(): rotating_left = true
func _on_rotate_left_button_up(): rotating_left = false
func _on_rotate_right_button_down(): rotating_right = true
func _on_rotate_right_button_up(): rotating_right = false
