extends StaticBody3D

@export var power_type: String = "Object"
@export var power_scene_name = "gluetrap"
@export var cost = 6

var stuck_balls: Array[Node] = []
var triggered: bool = false
var triggered_turn_num: int = -1
var removing: bool = false
var placed: bool = false

func _ready() -> void:
	add_to_group("trap")
	$Area3D.body_entered.connect(_on_area_body_entered)
	$Area3D.body_exited.connect(_on_area_body_exited)

func canPlace() -> bool:
	var bodies = $Area3D.get_overlapping_areas()
	return bodies.size() == 0

func mark_placed() -> void:
	placed = true

func _on_area_body_entered(body: Node) -> void:
	if not placed:
		return
	if not body or not body is RigidBody3D:
		return

	if not stuck_balls.has(body):
		stuck_balls.append(body)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.freeze = true

	if not triggered:
		triggered = true
		var main = _find_main()
		if main:
			triggered_turn_num = main.turn_num

func _on_area_body_exited(body: Node) -> void:
	if not placed:
		return
	if not body or not body is RigidBody3D:
		return

	if stuck_balls.has(body):
		stuck_balls.erase(body)
		body.freeze = false

func _physics_process(delta: float) -> void:
	if not placed:
		return
	if removing:
		return
	if triggered and _should_remove_trap():
		removing = true
		_release_all_stuck_balls()
		_disable_trap_collision()
		_decrement_main_objects()
		queue_free()

func _should_remove_trap() -> bool:
	var main = _find_main()
	if not main:
		return false
	if triggered_turn_num < 0:
		return false
	if main.turn_num < triggered_turn_num:
		return false
	var ball_manager = _find_ball_manager()
	if not ball_manager:
		return false
	if not ball_manager.has_method("check_all_not_moving"):
		return false
	return ball_manager.check_all_not_moving()

func _decrement_main_objects() -> void:
	var main = _find_main()
	if not main:
		return
	var current_objects = main.get("objects")
	if typeof(current_objects) == TYPE_NIL:
		return
	if not main.multiplayer.is_server():
		return
	main.objects = max(int(current_objects) - 1, 0)

func _release_all_stuck_balls() -> void:
	for body in stuck_balls:
		if body and body.is_inside_tree():
			body.freeze = false
			if body is RigidBody3D:
				body.sleeping = false
	for body in $Area3D.get_overlapping_bodies():
		if body and body is RigidBody3D:
			body.freeze = false
			body.sleeping = false
	stuck_balls.clear()

func _disable_trap_collision() -> void:
	collision_layer = 0
	collision_mask = 0
	$Area3D.monitoring = false
	$Area3D.monitorable = false
	$Area3D.collision_layer = 0
	$Area3D.collision_mask = 0
	$CollisionShape3D.disabled = true
	$Area3D/CollisionShape3D.disabled = true

func _find_main() -> Node:
	# Prefer the local owning Game node in multiplayer lobby paths like
	# /root/MultiplayerLobby/Games/GameContainerX/SubViewportContainer/SubViewport/Game
	var node: Node = self
	while node:
		if node.name == "Game":
			return node
		node = node.get_parent()

	# If the trap is inside a SubViewport, resolve the Game from that viewport only.
	var viewport := get_viewport()
	if viewport:
		var viewport_game = viewport.get_node_or_null("Game")
		if viewport_game:
			return viewport_game

	var root = get_tree().get_root()
	var main = root.find_node("Main", true, false)
	if main and main.is_ancestor_of(self):
		return main
	var game = root.find_node("Game", true, false)
	if game and game.is_ancestor_of(self):
		return game
	var ball_manager = root.find_node("BallManager", true, false)
	if ball_manager and ball_manager.is_ancestor_of(self) and ball_manager.get_parent():
		return ball_manager.get_parent()
	return null

func _find_ball_manager() -> Node:
	var main = _find_main()
	if main:
		var local_ball_manager = main.get_node_or_null("BallManager")
		if local_ball_manager:
			return local_ball_manager

	var root = get_tree().get_root()
	var fallback = root.find_node("BallManager", true, false)
	if fallback and fallback.is_ancestor_of(self):
		return fallback
	return null
