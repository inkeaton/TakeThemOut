extends State

func enter(_msg: Dictionary = {}) -> void:
	body.update_debug_label("IDLE (Mind Querying)")
	# Stop moving
	nav_agent.target_position = body.global_position
	body.velocity = Vector2.ZERO
