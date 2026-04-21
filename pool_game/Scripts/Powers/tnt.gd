extends StaticBody3D

@export var power_type: String = "Modifier"
@export var power_scene_name = "tnt"
@export var cost = 10

func _ready() -> void:
	add_to_group("modifiers")

func get_target() -> String:
	var targets := _get_overlapping_object_targets()
	if targets.size() == 1:
		return str(targets[0].get_path())
	return ""

func apply_to(target: Node) -> void:
	if not _is_object_power(target):
		return
	target.queue_free()
	var main = get_node_or_null("/root/Main")
	if main:
		var current_objects = main.get("objects")
		if typeof(current_objects) != TYPE_NIL:
			main.objects = max(int(current_objects) - 1, 0)

func canPlace() -> bool:
	return _get_overlapping_object_targets().size() == 1

func _get_overlapping_object_targets() -> Array[Node]:
	var targets: Array[Node] = []
	var seen: Dictionary = {}
	for area in $Area3D.get_overlapping_areas():
		var parent = area.get_parent()
		if parent and parent != self and _is_object_power(parent):
			var key = parent.get_path()
			if not seen.has(key):
				seen[key] = true
				targets.append(parent)

	for body in $Area3D.get_overlapping_bodies():
		if body and body != self and _is_object_power(body):
			var body_key = body.get_path()
			if not seen.has(body_key):
				seen[body_key] = true
				targets.append(body)
	return targets

func _is_object_power(node: Node) -> bool:
	if not node:
		return false
	return str(node.get("power_type")) == "Object"
