## SentryAlertState: Executes short alert phase, scans allies, and reports completion.
extends State

# --- Behavior ---
## Alert state: Vision disabled, scans for allies, notifies mind.
## On timeout, transitions to Idle and notifies mind.

# --- Configuration ---
@export var alert_duration: float = 5.0

# --- State ---
var _timer: float = 0.0

# Initialized lazily on first `enter` call.
var alert_scanner: ShapeCast2D 

# --- Lifecycle ---
func enter(_msg: Dictionary = {}) -> void:
	body.update_debug_label("ALERT!")
	if not alert_scanner:
		alert_scanner = body.alert_scanner

	Messages.print_message("Alert sequence triggered!", "Sentry")
	
	# 1. Disable normal vision
	body.vision_cone.visible = false
	body.vision_cone.monitoring = false
	
	# 2. Perform the Ally Scan
	_perform_scan()
	
	# 3. Start timer - use passed duration or default
	var duration = _msg.get("duration", alert_duration)
	_timer = duration

# --- Physics Update ---
func update_physics(delta: float) -> void:
	_timer -= delta
	if _timer <= 0:
		_finish_alert()

# --- Helpers ---
func _perform_scan() -> void:
	alert_scanner.enabled = true
	alert_scanner.force_shapecast_update()
	
	var ally_names: Array[String] = []
	
	for i in range(alert_scanner.get_collision_count()):
		var collider = alert_scanner.get_collider(i)
		
		# Filter: Must be a guard, and must not be self
		if collider.is_in_group("guards") and collider != body:
			ally_names.append(collider.name)
	
	alert_scanner.enabled = false
	
	Messages.print_message("Found allies: " + str(ally_names), "Sentry")
	vesna.send_allies_found(ally_names)


# --- Completion ---
func _finish_alert() -> void:
	alert_scanner.enabled = false
	vesna.send_signal("alert", "completed", "Alert sequence finished")
	state_machine.change_state_by_name("Idle")
