extends State

## Scan state: Vision enabled, actively scanning for players.
## On player detection, body transitions to Idle and notifies mind.

@export var switch_time: float = 2.0
var _timer: float = 0.0

func enter(_msg: Dictionary = {}) -> void:
	body.update_debug_label("Scanning...")
	# Enable vision cone for active scanning
	body.vision_cone.visible = true
	body.vision_cone.monitoring = true
	body.vision_cone.modulate = Color.WHITE
	
	_timer = switch_time
	Messages.print_message("Scanning...", "Sentry")

func update_physics(delta: float) -> void:
	# Handle Rotation Logic
	_timer -= delta
	if _timer <= 0:
		body.rotate_viewpoint()
		_timer = switch_time
