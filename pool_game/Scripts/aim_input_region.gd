extends Control

signal aim_changed(touch_pos: Vector2)

var dragging := false

func _gui_input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			dragging = true
			emit_signal("aim_changed", event.position)
		else:
			dragging = false

	elif event is InputEventScreenDrag:
		if dragging:
			emit_signal("aim_changed", event.position)

	elif event is InputEventMouseButton:
		if event.pressed:
			dragging = true
			emit_signal("aim_changed", event.position)
		else:
			dragging = false
