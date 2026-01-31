extends State

@export var alert_duration: float = 5.0
var _timer: float = 0.0

# FIX: Remove @onready. We initialize this lazily.
var alert_scanner: ShapeCast2D 

func enter(_msg: Dictionary = {}) -> void:
	# FIX: Assign reference here, the first time we enter the state
	if not alert_scanner:
		alert_scanner = body.alert_scanner

	Messages.print_message("Alert sequence triggered!", "Sentry")
	
	# 1. Disable normal vision (focusing on comms)
	body.vision_cone.visible = false
	body.vision_cone.monitoring = false
	
	# 2. Perform the Ally Scan
	_perform_scan()
	
	# 3. Start timer to return to normal
	_timer = alert_duration

func update_physics(delta: float) -> void:
	_timer -= delta
	if _timer <= 0:
		_finish_alert()

func _perform_scan() -> void:
	alert_scanner.force_shapecast_update()
	
	var ally_names: Array[String] = []
	
	for i in range(alert_scanner.get_collision_count()):
		var collider = alert_scanner.get_collider(i)
		
		# Filter: Must be a guard, and must not be self
		if collider.is_in_group("guards") and collider != body:
			ally_names.append(collider.name)
	
	Messages.print_message("Found allies: " + str(ally_names), "Sentry")
	vesna.send_allies_found(ally_names)

func _finish_alert() -> void:
	alert_scanner.enabled = false
	vesna.send_signal("alert", "completed", "Alert sequence finished")
	state_machine.change_state_by_name("Scan")
