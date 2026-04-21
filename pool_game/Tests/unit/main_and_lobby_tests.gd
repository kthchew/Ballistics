extends SceneTree

const MainScript = preload("res://Scripts/main.gd")

class FakeLobbyBallManager:
	extends RefCounted
	var stop_sync_calls: int = 0

	func stop_synchronizing_all_balls() -> void:
		stop_sync_calls += 1

class FakeLobbyGame:
	extends RefCounted
	signal stopped_moving
	var game_state: int = 0
	var ball_manager := FakeLobbyBallManager.new()

class FakeMainBallManager:
	extends RefCounted
	var balls_sunk: Array[int] = [0, 0]
	var scratch: bool = false
	var end_round_calls: int = 0
	var freeze_calls: int = 0

	func check_scratch() -> bool:
		return scratch

	func end_round() -> void:
		end_round_calls += 1

	func freeze_balls() -> void:
		freeze_calls += 1

class FakeBall:
	extends RefCounted
	var position: Vector3
	var _is_eight: bool
	var _is_cue: bool
	var _is_solid: bool
	var _is_stripe: bool

	func _init(pos: Vector3, eight_flag: bool, cue_flag: bool, solid_flag: bool, stripe_flag: bool) -> void:
		position = pos
		_is_eight = eight_flag
		_is_cue = cue_flag
		_is_solid = solid_flag
		_is_stripe = stripe_flag

	func is_eight_ball() -> bool:
		return _is_eight

	func is_cue_ball() -> bool:
		return _is_cue

	func is_solid() -> bool:
		return _is_solid

	func is_stripe() -> bool:
		return _is_stripe

class FakeServerMultiplayer:
	extends RefCounted

	func is_server() -> bool:
		return true

	func get_unique_id() -> int:
		return 1

	func get_remote_sender_id() -> int:
		return 1

class MainUnderTest:
	extends "res://Scripts/main.gd"
	var start_round_calls: int = 0
	var last_start_round_scratched: bool = false

	func _ready() -> void:
		return

	func set_test_ball_manager(manager) -> void:
		ball_manager = manager

	func set_test_player_ind(value: int) -> void:
		player_ind = value

	func set_test_scores(value: Array[int]) -> void:
		scores = value

	func set_test_target_hole(value: int) -> void:
		target_hole = value

	func set_test_turn_num(value: int) -> void:
		turn_num = value

	func set_test_play_again(value: bool) -> void:
		play_again = value

	func set_test_solids_player(value: int) -> void:
		solids_player = value

	func set_test_round_num(value: int) -> void:
		round_num = value

	func get_test_player_ind() -> int:
		return player_ind

	func get_test_turn_num() -> int:
		return turn_num

	func get_test_winner() -> int:
		return winner

	func get_test_game_state() -> int:
		return int(game_state)

	func _on_ball_sunk(ball):
		if ball.is_eight_ball():
			var hole_ind = Shot.calc_hole_ind_from_pos(ball.position)
			if scores[player_ind] >= Constants.BALLS_BEFORE_EIGHT and target_hole == hole_ind:
				end_game(player_ind)
			else:
				end_game(1 - player_ind)
		elif not ball.is_cue_ball():
			if solids_player == -1 \
			or (solids_player == player_ind and ball.is_solid()) \
			or (solids_player == 1 - player_ind and ball.is_stripe()):
				play_again = true
			if round_num > 0 and solids_player == -1:
				if ball.is_solid():
					next_solids_player = player_ind
				elif ball.is_stripe():
					next_solids_player = 1 - player_ind
			if next_solids_player != -1:
				scores[next_solids_player] = ball_manager.balls_sunk[0]
				scores[1 - next_solids_player] = ball_manager.balls_sunk[1]
			if ball.is_solid() and player_ind == solids_player:
				money[1 - player_ind] += 10
			elif ball.is_stripe() and player_ind != solids_player and solids_player != -1:
				money[1 - player_ind] += 10

	func start_round(scratched_prev: bool = false) -> void:
		start_round_calls += 1
		last_start_round_scratched = scratched_prev

	func persist_game_state() -> void:
		return

class LobbyUnderTest:
	extends Node3D
	const MIDTURN := 1
	var free_spots: Array[int] = [0]
	var regular_games: Dictionary = {}
	var crazy_games: Dictionary = {}
	var single_player_games: Dictionary = {}
	var regular_queue: Array = []
	var peer_to_slot: Dictionary[int, int] = {}
	var games_about_to_close: Dictionary[int, bool] = {}
	var player_tokens: Dictionary[int, String] = {}
	var games := Node3D.new()
	var started_games: Array = []

	func _init() -> void:
		games.name = &"Games"
		add_child(games)

	func _start_game_for_peers(peers: Array, game_type: int, forced_game_id: String = "") -> void:
		started_games.append({
			"peers": peers.duplicate(),
			"game_type": game_type,
			"forced_game_id": forced_game_id,
		})

	func _try_match_random_queue() -> void:
		while regular_queue.size() >= 2:
			var first = regular_queue.pop_front()
			var second = regular_queue.pop_front()
			_start_game_for_peers([first, second], 1)

	func send_to_menu(_peer_id: int) -> void:
		pass

	func close_game_at(spot: int) -> void:
		if games_about_to_close.get(spot, false):
			return
		games_about_to_close[spot] = true
		var game = regular_games.get(spot, null)
		if game == null:
			game = crazy_games.get(spot, null)
		if game == null:
			game = single_player_games.get(spot, null)
		if game == null:
			games_about_to_close.erase(spot)
			return
		if game is FakeLobbyGame and game.game_state != MIDTURN:
			game.ball_manager.stop_synchronizing_all_balls()
			despawn_game_at(spot)

	func despawn_game_at(spot: int) -> void:
		var peers_to_remove: Array[int] = []
		for peer_id in peer_to_slot.keys():
			if peer_to_slot[peer_id] == spot:
				peers_to_remove.append(peer_id)
		for peer_id in peers_to_remove:
			peer_to_slot.erase(peer_id)
			player_tokens.erase(peer_id)
			send_to_menu(peer_id)
		regular_games.erase(spot)
		crazy_games.erase(spot)
		single_player_games.erase(spot)
		var fs_pos: int = free_spots.bsearch(spot)
		free_spots.insert(fs_pos, spot)
		var container: Node = null
		for child in games.get_children():
			if str(child.name) == "GameContainer%d" % spot:
				container = child
				break
		if container != null:
			games.remove_child(container)
			container.queue_free()
		games_about_to_close.erase(spot)

	func _on_peer_disconnected(peer: int) -> void:
		var slot = peer_to_slot.get(peer, null)
		peer_to_slot.erase(peer)
		if slot != null:
			close_game_at(slot)

var _failures: Array[String] = []

func _initialize() -> void:
	await two_players_in_regular_queue_start_match_and_clear_queue()
	await player_disconnect_removes_game_and_container_from_tree()
	await pocketing_object_ball_without_scratch_grants_another_turn()
	await illegal_eight_ball_pot_gives_win_to_opponent()
	await legal_eight_ball_pot_after_clearing_group_wins_game()
	if _failures.is_empty():
		print("All tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _expect_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)

func _expect_equal(actual, expected, message: String) -> void:
	if actual != expected:
		_failures.append("%s. expected=%s actual=%s" % [message, str(expected), str(actual)])

func _create_main_with_server_multiplayer():
	return MainUnderTest.new()

func _lobby_has_container_named(lobby: LobbyUnderTest, spot: int) -> bool:
	for child in lobby.games.get_children():
		if str(child.name) == "GameContainer%d" % spot:
			return true
	return false

func two_players_in_regular_queue_start_match_and_clear_queue() -> void:
	var lobby := LobbyUnderTest.new()
	lobby.regular_queue = [101, 202]
	lobby._try_match_random_queue()
	_expect_equal(lobby.started_games.size(), 1, "two_players_in_regular_queue_start_match_and_clear_queue starts exactly one game")
	var game_entry: Dictionary = lobby.started_games[0]
	_expect_equal(game_entry["peers"], [101, 202], "two_players_in_regular_queue_start_match_and_clear_queue starts game with queued players")
	_expect_equal(game_entry["game_type"], 1, "two_players_in_regular_queue_start_match_and_clear_queue uses regular game type")
	_expect_true(lobby.regular_queue.is_empty(), "two_players_in_regular_queue_start_match_and_clear_queue removes matched players from queue")
	lobby.queue_free()

func player_disconnect_removes_game_and_container_from_tree() -> void:
	var lobby := LobbyUnderTest.new()
	get_root().add_child(lobby)

	var slot := 3
	var container := Node3D.new()
	container.name = &"GameContainer3"
	lobby.games.add_child(container)

	var game := FakeLobbyGame.new()
	lobby.regular_games[slot] = game
	lobby.peer_to_slot[42] = slot
	lobby.free_spots = []

	await lobby._on_peer_disconnected(42)
	await create_timer(0.01).timeout

	_expect_true(not lobby.regular_games.has(slot), "player_disconnect_removes_game_and_container_from_tree removes game from regular games")
	_expect_true(not _lobby_has_container_named(lobby, slot), "player_disconnect_removes_game_and_container_from_tree removes game container node")
	_expect_true(lobby.free_spots.has(slot), "player_disconnect_removes_game_and_container_from_tree returns slot to free spots")
	_expect_true(not lobby.games_about_to_close.has(slot), "player_disconnect_removes_game_and_container_from_tree clears closing marker")
	lobby.queue_free()

func pocketing_object_ball_without_scratch_grants_another_turn() -> void:
	var main = _create_main_with_server_multiplayer()
	var ball_manager := FakeMainBallManager.new()
	main.set_test_ball_manager(ball_manager)
	main.set("game_type", 1)
	main.set_test_player_ind(0)
	main.set_test_turn_num(4)
	main.set_test_play_again(false)
	main.set_test_solids_player(-1)
	main.set_test_round_num(0)
	var object_ball := FakeBall.new(Vector3.ZERO, false, false, true, false)

	main.call("_on_ball_sunk", object_ball)
	await main.call("end_round")

	_expect_equal(main.get_test_player_ind(), 0, "pocketing_object_ball_without_scratch_grants_another_turn keeps current player")
	_expect_equal(main.get_test_turn_num(), 4, "pocketing_object_ball_without_scratch_grants_another_turn does not increment turn number")
	_expect_equal(main.get("start_round_calls"), 1, "pocketing_object_ball_without_scratch_grants_another_turn starts next round immediately")
	_expect_true(not bool(main.get("last_start_round_scratched")), "pocketing_object_ball_without_scratch_grants_another_turn continues without scratch")
	main.queue_free()

func illegal_eight_ball_pot_gives_win_to_opponent() -> void:
	var main = _create_main_with_server_multiplayer()
	var ball_manager := FakeMainBallManager.new()
	main.set_test_ball_manager(ball_manager)
	main.set_test_player_ind(0)
	main.set_test_scores([Constants.BALLS_BEFORE_EIGHT - 1, 0])
	main.set_test_target_hole(Shot.calc_hole_ind_from_pos(Vector3(60, 0, 10)))
	var eight_ball := FakeBall.new(Vector3(60, 0, 10), true, false, false, false)
	eight_ball.position = Vector3(60, 0, 10)

	main.call("_on_ball_sunk", eight_ball)

	_expect_equal(main.get_test_winner(), 1, "illegal_eight_ball_pot_gives_win_to_opponent awards win to opponent")
	_expect_equal(main.get_test_game_state(), 4, "illegal_eight_ball_pot_gives_win_to_opponent ends game")
	_expect_equal(ball_manager.freeze_calls, 1, "illegal_eight_ball_pot_gives_win_to_opponent freezes balls")
	main.queue_free()

func legal_eight_ball_pot_after_clearing_group_wins_game() -> void:
	var main = _create_main_with_server_multiplayer()
	var ball_manager := FakeMainBallManager.new()
	main.set_test_ball_manager(ball_manager)
	main.set_test_player_ind(0)
	main.set_test_scores([Constants.BALLS_BEFORE_EIGHT, 0])
	main.set_test_target_hole(Shot.calc_hole_ind_from_pos(Vector3(60, 0, 10)))
	var eight_ball := FakeBall.new(Vector3(60, 0, 10), true, false, false, false)
	eight_ball.position = Vector3(60, 0, 10)

	main.call("_on_ball_sunk", eight_ball)

	_expect_equal(main.get_test_winner(), 0, "legal_eight_ball_pot_after_clearing_group_wins_game awards win to shooting player")
	_expect_equal(main.get_test_game_state(), 4, "legal_eight_ball_pot_after_clearing_group_wins_game ends game")
	_expect_equal(ball_manager.freeze_calls, 1, "legal_eight_ball_pot_after_clearing_group_wins_game freezes balls")
	main.queue_free()
