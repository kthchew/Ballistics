extends AIController3D

var action_angle = 0.0
var action_power = 0.0
var action_posx = 0.0
var action_posy = 0.0

var eight_ball_sunk = false
var cue_ball_sink_count = 0

signal fire

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass



func _ready():
	reset_after = 2
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
	
	var cue_ball = $"../CueBall"
	var cue_pos = cue_ball.position
	obs.append_array([
		cue_pos.x / 109, #-1->1 
		#clamp(((cue_pos.y / 2.85) - 1) / 2, -1, 1), #0 on table, 1 above, -1 below
		(cue_pos.z + 53) / (2 * 53) #0->1
	])
	for ball in balls.slice(1):
		var x_diff = ball.position.x - cue_ball.position.x
		var z_diff = ball.position.z - cue_ball.position.z
		obs.append_array([
			1.0 if ball.is_visible() else 0.0,
			x_diff / 218 if ball.is_visible() else 0.0,
			z_diff / 106 if ball.is_visible() else 0.0
		])
		
	#print(obs)
	return {"obs": obs}


func get_reward() -> float:
	return reward


func get_action_space() -> Dictionary:
	return {
		# [0]: sin, [1]: cos
		"angle-topdown": {"size": 2, "action_type": "continuous"},
		"power": {"size": 1, "action_type": "continuous"},
		"ball_pos": {"size": 2, "action_type": "continuous"}
	}

func get_info() -> Dictionary:
	if done: 
		return {
			"solids_sunk": $"..".balls_sunk[0],
			"stripes_sunk": $"..".balls_sunk[1],
			"eight_ball_sunk": eight_ball_sunk,
			"cue_ball_sink_count": cue_ball_sink_count
		}
	return {}

func set_action(action) -> void:
	var ang_mag = sqrt((action["angle-topdown"][0] ** 2) + (action["angle-topdown"][1] ** 2) + 1e-8)
	action_angle = atan2(action["angle-topdown"][0] / ang_mag, action["angle-topdown"][1] / ang_mag)
	action_power = clamp(((action["power"][0] + 1) / 2.105) + 0.05, 0, 1)
	action_posx = clamp(action["ball_pos"][0], -1, 1)
	action_posy = clamp(action["ball_pos"][1], -1, 1)
	#action_posx = 0
	#action_posy = 0
	fire.emit()


#-----------------------------------------------------------------------------#


#-- Methods that sometimes need implementing using the "extend script" option in Godot --#
# Only needed if you are recording expert demos with this AIController
func get_action() -> Array:
	assert(false, "the get_action method is not implemented in extended AIController but demo_recorder is used")
	return []

# -----------------------------------------------------------------------------#

func increment_n_steps():
	n_steps += 1
	if n_steps > reset_after:
		$"..".add_to_ewma(false)
		done = true
		needs_reset = true

func _physics_process(delta):
	pass


func get_obs_space():
	# may need overriding if the obs space is complex
	var obs = get_obs()
	return {
		"obs": {"size": [len(obs["obs"])], "space": "box"},
	}


func reset():
	n_steps = 0
	cue_ball_sink_count = 0
	eight_ball_sunk = false
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
