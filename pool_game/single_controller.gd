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
	reset_after = 100000
	add_to_group("AGENT")


func init(player: Node3D):
	_player = player


func sort_balls_by_num(a, b):
	return (a.ball_num < b.ball_num)

#-- Methods that need implementing using the "extend script" option in Godot --#
func get_obs() -> Dictionary:
	var balls = _player.balls
	balls.sort_custom(sort_balls_by_num)
	var obs = []
	for ball in balls: 
		var pos = ball.position
		obs.append_array([
			pos.x / 109, #-1->1 
			clamp(((pos.y / 2.85) - 1) / 2, -1, 1), #0 on table, 1 above, -1 below
			(pos.z + 53) / (2 * 53) #0->1
		])
	return {"obs": obs}


func get_reward() -> float:
	return reward


func get_action_space() -> Dictionary:
	return {
		# [0]: sin, [1]: cos
		"angle-topdown": {"size": 2, "action_type": "continuous"},
		"power": {"size": 1, "action_type": "continuous"},
		#"ball_pos": {"size": 2, "action_type": "continuous"}
	}


func set_action(action) -> void:
	var ang_mag = sqrt(((action["angle-topdown"][0]) ** 2) + ((action["angle-topdown"][1]) ** 2) + 1e-8)
	action_angle = atan2(action["angle-topdown"][0] / ang_mag, action["angle-topdown"][1] / ang_mag)
	action_power = clamp(((action["power"][0] + 1) / 2.105) + 0.05, 0, 1)
	#action_posx = clamp(action["ball_pos"][0], -1, 1)
	#action_posy = clamp(action["ball_pos"][1], -1, 1)
	action_posx = 0
	action_posy = 0
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
	#if reward != 0:
		#print("reward zeroing (was " + str(reward) + ")")
	reward = 0.0
