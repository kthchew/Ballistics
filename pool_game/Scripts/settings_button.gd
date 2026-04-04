extends Button

@onready var settingsScreen = $"../SettingsScreen"

func _ready():
	pressed.connect(_on_pressed)

func _on_pressed():
	settingsScreen.show()
