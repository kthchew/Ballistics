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
	"block": preload("res://Scenes/Powers/Block.tscn"),
	"tnt": preload("res://Scenes/Powers/TNT.tscn"),
	"tungsten": preload("res://Scenes/Powers/Tungsten.tscn"),
	"aerogel": preload("res://Scenes/Powers/Aerogel.tscn")
}

func _ready():
	game_root = get_node("../..")
	preview_container = game_root.get_node("PreviewContainer")

@rpc("authority", "call_local")
func set_cashout_owner(owner_peer_id: int):
	self.owner_peer_id = owner_peer_id

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
		print("multiplayer.get_unique_id() != owner_peer_id")
		return
	if not preview:
		print("not preview")
		return

	var power_cost = preview.cost
	
	if power_cost <= 0:
		print("power_cost <= 0")
		return
	if not game_root or not game_root.purchase_power(power_name, power_cost):
		if not game_root:
			print("not game_root")
		if not game_root.purchase_power(power_name, power_cost):
			print("not game_root.purchase_power(power_name, power_cost)")
		return

	var target_path = ""
	if preview.power_type == "Modifier":
		target_path = preview.get_target()
		
	print("reached end")
	print(preview.global_position)
	request_place_power.rpc(
		preview.power_type,
		preview.global_position,
		preview.global_rotation,
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
		game_root.objects += 1

	return obj

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

	var scene: PackedScene = power_scenes.get(pName)
	if not scene:
		return

	var power_instance = scene.instantiate()
	preview_container.add_child(power_instance)

	if power_instance.has_method("apply_to"):
		power_instance.apply_to(target)

	power_instance.queue_free()

@rpc("any_peer", "reliable")
func rpc_apply_modifier(pName: String, modified_path: String) -> void:
	_apply_modifier(pName, modified_path)

@rpc("any_peer", "reliable")
func request_place_power(power_type: String, pos: Vector3, rot: Vector3, pName: String, target_path: String = ""):
	print(pos)
	if not multiplayer.is_server():
		print("not a server")
		return
	
	print("server")
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
	
	if not power_instance.canPlace():
		print("not power_instance.canPlace()")
		power_instance.queue_free()
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
	print("finish placement")
	finish_placement.rpc_id(sender)


@rpc("any_peer", "call_local")
func finish_placement():
	self.visible = false
	if preview:
		preview.queue_free()
		preview = null
	if power_name != null and game_root:
		if not game_root.power_shop_used.has(power_name):
			game_root.power_shop_used.append(power_name)
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

		# set_preview_illegal(not preview.canPlace())

func _on_rotate_left_button_down(): rotating_left = true
func _on_rotate_left_button_up(): rotating_left = false
func _on_rotate_right_button_down(): rotating_right = true
func _on_rotate_right_button_up(): rotating_right = false
