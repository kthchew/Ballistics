extends Control

@export var radius := 100.0
@export var is_right := false

var dragging := false
var output := Vector2.ZERO
var touch_index := -1

@onready var knob := $Knob

func _gui_input(event):
	if event is InputEventScreenTouch:
		if event.pressed and touch_index == -1:
			touch_index = event.index
			dragging = true
			_update_knob(get_local_mouse_position())
		elif not event.pressed and event.index == touch_index:
			touch_index = -1
			dragging = false
			output = Vector2.ZERO
			_reset_knob()
		return

	if event is InputEventScreenDrag and event.index == touch_index and dragging:
		_update_knob(get_local_mouse_position())

func _update_knob(local_pos: Vector2):
	# local_pos is already Control-local
	local_pos -= size * 0.5

	var clamped := local_pos.limit_length(radius)
	output = clamped / radius

	knob.position = clamped + (size * 0.5) - (knob.size * 0.5)

func _reset_knob():
	knob.position = (size * 0.5) - (knob.size * 0.5)
