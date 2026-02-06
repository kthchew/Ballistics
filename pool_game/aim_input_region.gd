extends Control

signal aim_changed(touch_pos: Vector2)

var dragging := false

func _gui_input(event):
	if event is InputEventScreenTouch:
		dragging = event.pressed

	if dragging and event is InputEventScreenDrag:
		emit_signal("aim_changed", event.position)
