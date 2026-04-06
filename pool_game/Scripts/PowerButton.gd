extends Button

func _ready():
	pressed.connect(_on_pressed)

func _on_pressed():
	var parent = get_parent()
	parent.get_parent().visible = false
