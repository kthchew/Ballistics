extends Button

@onready var accountScreen = $"../AccountScreen"

func _ready():
	pressed.connect(_on_pressed)

func _on_pressed():
	pass
