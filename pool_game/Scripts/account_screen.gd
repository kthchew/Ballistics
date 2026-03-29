extends Control

var login = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$HBoxContainer/ConfirmButton.pressed.connect(_on_confirm_pressed)
	$"ProfileTestButton".pressed.connect(_on_profiletest_pressed)
	$HBoxContainer/CloseButton.pressed.connect(_on_close_pressed)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func _on_confirm_pressed() -> void:
	var username = $VBoxContainer/UsernameInput.text
	var password = $VBoxContainer/PasswordInput.text
	var login_selected = $HBoxContainer2/LoginOptionButton.button_pressed
	var register_selected = $HBoxContainer2/RegisterOptionButton.button_pressed
	
	print("Username: " + username + ", Password: " + password)
	if login_selected:
		print("Login selected")
		$BackendRequests.login(username, password)
	elif register_selected:
		print("Register selected")
		$BackendRequests.register(username, password)
		
func _on_profiletest_pressed() -> void:
	$BackendRequests.profile_test_endpoint()
	
func _on_close_pressed() -> void:
	visible = false
