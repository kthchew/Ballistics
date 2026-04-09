extends Node3D

@onready var subviewport_container: SubViewportContainer = $SubViewportContainer
@onready var subviewport: SubViewport = $SubViewportContainer/SubViewport

func _ready() -> void:
	_sync_subviewport_size()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_sync_subviewport_size):
		viewport.size_changed.connect(_sync_subviewport_size)

func _sync_subviewport_size() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var visible_size := viewport.get_visible_rect().size
	var target_size := Vector2i(max(1, int(visible_size.x)), max(1, int(visible_size.y)))
	subviewport_container.size = visible_size
	subviewport_container.stretch = true
	if subviewport.size != target_size:
		subviewport.size = target_size
	var game: Node = subviewport.get_node("Game")
	var hole_buttons: Node = game.get_node("UI/HoleButtons")
	var cue_stick: Node = game.get_node("UI/AimVisuals/CueStick")
	var safe_area_container: Node = game.get_node("UI/SafeAreaContainer")
	
	hole_buttons.reposition_hole_buttons()
	
	var aim_dir = cue_stick.aim_direction
	game.cast_aim_ray(Vector2(aim_dir.x, aim_dir.z))
	
	# set container size to be within the safe area
	var safe_area := DisplayServer.get_display_safe_area()
	# convert subviewport coordinates (origin at 0,0) to physical screen coordinates (origin at window position)
	var rel_subviewport_rect := Rect2(Vector2.ZERO, subviewport.size)
	var window_rect := Rect2(get_window().position, get_window().size)
	var subviewport_rect := Transform2D().translated(window_rect.position - rel_subviewport_rect.position) * rel_subviewport_rect
	if safe_area.intersects(subviewport_rect):
		var intersection := safe_area.intersection(subviewport_rect)
		var margin_left = max(0, intersection.position.x - subviewport_rect.position.x)
		var margin_top = max(0, intersection.position.y - subviewport_rect.position.y)
		var margin_right = max(0, (subviewport_rect.position.x + subviewport_rect.size.x) - (intersection.position.x + intersection.size.x))
		var margin_bottom = max(0, (subviewport_rect.position.y + subviewport_rect.size.y) - (intersection.position.y + intersection.size.y))
		safe_area_container.position.x = margin_left
		safe_area_container.position.y = margin_top
		safe_area_container.size.x = subviewport_rect.size.x - margin_left - margin_right
		safe_area_container.size.y = subviewport_rect.size.y - margin_top - margin_bottom
	
