extends State

@export var switch_time: float = 2.0
var _timer: float = 0.0

func enter(_msg: Dictionary = {}) -> void:
	# Reset visuals to "Normal"
	body.vision_cone.visible = true
	body.vision_cone.monitoring = true
	body.vision_cone.modulate = Color.WHITE
	
	_timer = switch_time
	Messages.print_message("Resuming Patrol.", "Sentry")

func update_physics(delta: float) -> void:
	# Handle Rotation Logic
	_timer -= delta
	if _timer <= 0:
		body.rotate_viewpoint()
		_timer = switch_time
