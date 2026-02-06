extends Node2D

@onready var line := $Line2D

@export var min_length := 50.0
@export var max_length := 120.0

var angle := 0.0

func set_angle(a: float):
	angle = a
	rotation = angle

func set_force_strength(strength: float):
	strength = clamp(strength, 0.0, 1.0)
	var length = lerp(min_length, max_length, strength)

	var pts : PackedVector2Array = line.points
	pts[1] = Vector2(length, 0)
	line.points = pts
