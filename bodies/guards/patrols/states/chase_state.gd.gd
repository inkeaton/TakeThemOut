extends State

@export var chase_path_refresh_interval: float = 0.1
var _chase_cooldown: float = 0.0

func enter(msg: Dictionary = {}) -> void:
	body.update_debug_label("CHASING PLAYER!")
	# Start moving immediately
	if body.target_player:
		nav_agent.target_position = body.target_player.global_position
		
	# Store patience if we need to pass it to Track state later
	# (We can store it on the Body or locally)

func update_physics(delta: float) -> void:
	if not body.target_player:
		return
		
	_chase_cooldown -= delta
	if _chase_cooldown <= 0:
		nav_agent.target_position = body.target_player.global_position
		_chase_cooldown = chase_path_refresh_interval
