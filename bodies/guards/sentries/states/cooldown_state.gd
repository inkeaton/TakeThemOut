extends State

@export var detection_cooldown: float = 5.0 
var _timer: float = 0.0

func enter(_msg: Dictionary = {}) -> void:
	# Visual Feedback: "I saw something" (Teal/Yellow)
	body.vision_cone.modulate = Color(0.0, 0.668, 0.372, 0.6)
	_timer = detection_cooldown

func update_physics(delta: float) -> void:
	_timer -= delta
	
	# If the mind never replies with an Alert, eventually go back to scanning
	if _timer <= 0:
		state_machine.change_state_by_name("Scan")
