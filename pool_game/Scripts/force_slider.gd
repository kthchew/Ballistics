extends VSlider

@export var min_grabber_size: float = 20.0
@export var max_grabber_size: float = 60.0

@onready var grabber: Control = $GrabberVisual

var _wiggle_tween: Tween = null
var _original_pos: Vector2

func _process(delta: float) -> void:
	var t: float = 0.0
	if max_value != min_value:
		t = float(value - min_value) / float(max_value - min_value)
	else:
		t = 0.0

	# Size interpolation
	var size_val: float = lerp(min_grabber_size, max_grabber_size, t)
	grabber.size = Vector2(size_val, size_val)

	# Position along the slider
	var slider_size: Vector2 = size
	var usable_height: float = slider_size.y - size_val
	var y: float = (1.0 - t) * usable_height
	var x: float = (slider_size.x - size_val) * 0.5
	grabber.position = Vector2(x, y)

	# Shake intensity (stronger near red)
	var shake_strength: float = lerp(0.0, 2.0, t * t)
	var shake_offset: Vector2 = Vector2(
		randf_range(-shake_strength, shake_strength),
		randf_range(-shake_strength, shake_strength)
	)
	grabber.position += shake_offset

func wiggle() -> void:
	if _wiggle_tween and _original_pos:
		position = _original_pos
		_wiggle_tween.kill()
	_wiggle_tween = create_tween()
	_original_pos = position
	_wiggle_tween.tween_property(self, "position", _original_pos + Vector2(10, 0), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_wiggle_tween.tween_property(self, "position", _original_pos - Vector2(10, 0), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_wiggle_tween.tween_property(self, "position", _original_pos, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
