extends Control

@onready var server_address_edit: LineEdit = $MarginContainer/VBoxContainer/ServerAddress/LineEdit
@onready var server_port_edit: LineEdit = $MarginContainer/VBoxContainer/ServerPort/LineEdit

@onready var save_button: Button = $MarginContainer/VBoxContainer/SaveButton

var config := ConfigFile.new()

const config_path := "user://settings.cfg"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var err := config.load(config_path)
	if err != OK:
		print("No existing config file found, using defaults")
	else:
		print("Config loaded successfully")
		
	server_address_edit.text = config.get_value("network", "server_address", Constants.DEFAULT_GAME_SERVER_ADDRESS_DEV if OS.is_debug_build() else Constants.DEFAULT_GAME_SERVER_ADDRESS)
	server_port_edit.text = str(config.get_value("network", "server_port", 18361))
	
	save_button.pressed.connect(_on_save_button_pressed)

func _on_save_button_pressed():
	var server_addr := server_address_edit.text
	config.set_value("network", "server_address", server_addr)
	var server_port := int(server_port_edit.text)
	config.set_value("network", "server_port", server_port)
	var err := config.save(config_path)
	if err != OK:
		print("Error saving config: %s" % err)
	else:
		print("Config saved successfully")
	hide()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
