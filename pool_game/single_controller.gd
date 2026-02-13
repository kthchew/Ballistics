extends AIController3D

var action_angle = 0.0
var action_power = 0.0
var action_posx = 0.0
var action_posy = 0.0

signal fire

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass



func _ready():
	add_to_group("AGENT")


func init(player: Node3D):
	_player = player


#-- Methods that need implementing using the "extend script" option in Godot --#
func get_obs() -> Dictionary:
	var balls = _player.balls
	var obs = []
	for ball in balls: 
		var pos = ball.global_position
		obs.append_array([pos.x, pos.y, pos.z])
	return {"obs": obs}


func get_reward() -> float:
	return reward


func get_action_space() -> Dictionary:
	return {
		"angle-topdown": {"size": 1, "action_type": "continuous"},
		"power": {"size": 1, "action_type": "continuous"},
		"ball_pos": {"size": 2, "action_type": "continuous"}
	}


func set_action(action) -> void:
	action_angle = clamp(action["angle-topdown"][0], -1, 1)
	action_power = clamp(action["power"][0], 0, 1)
	action_posx = clamp(action["ball_pos"][0], -1, 1)
	action_posy = clamp(action["ball_pos"][1], -1, 1)
	fire.emit()


#-----------------------------------------------------------------------------#


#-- Methods that sometimes need implementing using the "extend script" option in Godot --#
# Only needed if you are recording expert demos with this AIController
func get_action() -> Array:
	assert(false, "the get_action method is not implemented in extended AIController but demo_recorder is used")
	return []

# -----------------------------------------------------------------------------#


func _physics_process(delta):
	n_steps += 1
	if n_steps > reset_after:
		needs_reset = true


func get_obs_space():
	# may need overriding if the obs space is complex
	var obs = get_obs()
	return {
		"obs": {"size": [len(obs["obs"])], "space": "box"},
	}


func reset():
	n_steps = 0
	needs_reset = false


func reset_if_done():
	if done:
		reset()


func set_heuristic(h):
	# sets the heuristic from "human" or "model" nothing to change here
	heuristic = h


func get_done():
	return done


func set_done_false():
	done = false


func zero_reward():
	reward = 0.0
