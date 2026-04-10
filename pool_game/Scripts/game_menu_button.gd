extends Button

var tween: Tween = null
var default_color: Color

func _ready() -> void:
	default_color = modulate

func start_pulsing() -> void:
	# Godot 4.6, subtle flash of the button's color to indicate a request for attention
	if tween and tween.is_running():
		tween.stop()
	
	var brighter_color := Color(0.4, 0.4, 0.4)
	print(default_color)
	tween = create_tween()
	tween.tween_property(self, "modulate", brighter_color, 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "modulate", default_color, 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.set_loops()
	
func stop_pulsing() -> void:
	if tween and tween.is_running():
		tween.stop()
	modulate = default_color
