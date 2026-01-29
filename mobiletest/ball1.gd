extends RigidBody3D

var touch_id := -1
var start_pos := Vector2.ZERO

func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			var ray = get_viewport().get_camera_3d().project_ray_origin(event.position)
			var dir = get_viewport().get_camera_3d().project_ray_normal(event.position)
			var space_state = get_world_3d().direct_space_state
			var query := PhysicsRayQueryParameters3D.create(ray, ray + dir * 100)
			var hit := space_state.intersect_ray(query)


			if hit and hit["collider"] == self:
				touch_id = event.index
				start_pos = event.position

		else:
			if event.index == touch_id:
				var delta = event.position - start_pos
				apply_impulse(Vector3(delta.x, 0, delta.y) * 0.05)
				touch_id = -1
