extends Node

enum MatchmakingMode {
	RANDOM,
	PRIVATE_CREATE,
	PRIVATE_JOIN,
	RESUME
}

enum PlayerRole {STRIPES = 1, SOLIDS}
enum GameType {EIGHT_BALL_MULTIPLAYER = 1, EIGHT_BALL_SINGLEPLAYER, CRAZY_EIGHT_BALL_MULTIPLAYER, CRAZY_EIGHT_BALL_SINGLEPLAYER}
enum GameState {AIMING, MIDTURN, PLACING, PICKPOCKET, ENDED, NOT_STARTED}

var word_list: Array = []

func _ready() -> void:
	var file := FileAccess.open("res://Resources/word_list.txt", FileAccess.READ)
	if file:
		var content: String = file.get_as_text()
		word_list = content.split("\n")
