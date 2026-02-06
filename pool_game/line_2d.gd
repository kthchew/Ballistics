extends Line2D

func _ready():
	var pts: PackedVector2Array = points
	if pts.size() < 2:
		pts.resize(2)
		pts[0] = Vector2.ZERO
		pts[1] = Vector2(50, 0)
		points = pts

func _process(delta: float) -> void:
	pass
