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


func sort_balls_by_num(a, b):
	return (a.ball_num < b.ball_num)

#-- Methods that need implementing using the "extend script" option in Godot --#
func get_obs() -> Dictionary:
	var balls = _player.balls
	balls.sort_custom(sort_balls_by_num)
	var obs = [balls[1].position.x - balls[0].position.x, 
			   balls[1].position.z - balls[0].position.z]
	#for ball in balls: 
		#var pos = ball.position
		#obs.append_array([
			#pos.x / 109, #-1->1 
			#clamp(((pos.y / 2.85) - 1) / 2, -1, 1), #0 on table, 1 above, -1 below
			#(pos.z + 53) / (2 * 53) #0->1
		#])
	print("sending obs...")
	print(obs)
	return {"obs": obs}


func get_reward() -> float:
	return reward


func get_action_space() -> Dictionary:
	return {
		"angle-topdown": {"size": 1, "action_type": "continuous"},
	}


func set_action(action) -> void:
	action_angle = clamp(action["angle-topdown"][0], -1, 1)
	fire.emit()
