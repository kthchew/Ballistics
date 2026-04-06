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
	
	hole_buttons.reposition_hole_buttons()
	
	var aim_dir = cue_stick.aim_direction
	game.cast_aim_ray(Vector2(aim_dir.x, aim_dir.z))
