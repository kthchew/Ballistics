extends Node2D

@onready var cue_sprite: Sprite2D = $CueSprite

@export var min_length: float = 50.0
@export var max_length: float = 120.0
@export var max_pullback: float = 25.0

var angle: float = 0.0

func _ready() -> void:
	var tex := cue_sprite.texture

	cue_sprite.centered = false
	cue_sprite.offset = Vector2(0, -6)

	cue_sprite.scale = Vector2(1, 1)
	cue_sprite.position = Vector2.ZERO

func set_angle(a: float) -> void:
	angle = a
	rotation = angle + PI

func set_force_strength(strength: float) -> void:
	strength = clamp(strength, 0.0, 1.0)
	cue_sprite.position = Vector2(max_pullback * strength, 0)
