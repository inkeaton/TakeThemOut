extends CharacterBody2D

# --- Configuration ---
@export var look_angles : Array[float] = [0.0, 90.0, 180.0, 270.0]
@export var switch_time : float = 2.0
@export var detection_cooldown : float = 5.0 
@export var alert_duration : float = 1.0 # How long the "shout" lasts

# --- State ---
var current_look_index : int = 0
var target_player : CharacterBody2D = null
var is_on_cooldown : bool = false
var is_alerting : bool = false
var last_seen_player_position : Vector2 = Vector2.ZERO
var sight_reported : bool = false

# --- Nodes ---
@onready var vision_cone : Area2D = $VisionCone
@onready var alert_radius : Area2D = $AlertRadius
@onready var patrol_timer : Timer = $SwitchSide 
@onready var cooldown_timer : Timer = $CooldownTimer 
@onready var line_of_sight : RayCast2D = $LineOfSight
@onready var network : VesnaManager = $VesnaManager

func _ready() -> void:
	patrol_timer.wait_time = switch_time
	if not patrol_timer.timeout.is_connected(_on_patrol_timer_timeout):
		patrol_timer.timeout.connect(_on_patrol_timer_timeout)
	
	cooldown_timer.wait_time = detection_cooldown
	cooldown_timer.timeout.connect(_on_cooldown_timeout)
	
	# Ensure Alert Radius is off by default
	alert_radius.monitoring = false
	alert_radius.monitorable = false
	
	# Connect to VesnaManager for commands from the mind
	network.command_received.connect(_on_mind_command)
	
	update_facing_direction()

func _physics_process(_delta: float) -> void:
	# Only check vision if we are NOT cooling down AND NOT currently alerting
	if target_player and not is_on_cooldown and not is_alerting:
		check_line_of_sight()

func _on_patrol_timer_timeout() -> void:
	if not is_on_cooldown and not is_alerting:
		current_look_index = (current_look_index + 1) % look_angles.size()
		update_facing_direction()

func update_facing_direction() -> void:
	var angle_deg = look_angles[current_look_index]
	vision_cone.rotation_degrees = angle_deg
	
	var sprite = $Sprite
	if angle_deg > 90 and angle_deg < 270:
		sprite.flip_h = true
	else:
		sprite.flip_h = false

# --- Detection Logic ---

func _on_vision_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		target_player = body

func _on_vision_body_exited(body: Node2D) -> void:
	if body == target_player:
		target_player = null
		line_of_sight.enabled = false 
		sight_reported = false

func check_line_of_sight() -> void:
	if not target_player: return
	
	line_of_sight.target_position = to_local(target_player.global_position)
	line_of_sight.enabled = true
	line_of_sight.force_raycast_update()
	
	if line_of_sight.is_colliding():
		if line_of_sight.get_collider() == target_player and not sight_reported:
			# Store the last known position
			last_seen_player_position = target_player.global_position
			react_to_player()

func react_to_player() -> void:
	Messages.print_message("I SEE YOU! Notifying mind...", "Sentry")
	var player_id = target_player.get_instance_id() 
	sight_reported = true
	
	# Send sight with position to the mind - mind will decide what to do
	network.send_sight_with_position("player", player_id, last_seen_player_position)

# --- Mind Command Handler ---

func _on_mind_command(intention: Dictionary) -> void:
	var action_type = intention.get("type", "")
	var data = intention.get("data", {})
	
	match action_type:
		"alert":
			if data.get("type", "") == "start":
				trigger_alert_sequence()
		_:
			Messages.print_message("Unknown command from mind: " + action_type, "Sentry")

# --- Alert Logic (triggered by mind) ---

func trigger_alert_sequence() -> void:
	if is_alerting: return  # Prevent re-triggering
	
	is_alerting = true
	Messages.print_message("Alert sequence triggered by mind!", "Sentry")
	
	# 1. Deactivate Vision Cone
	vision_cone.monitoring = false
	vision_cone.visible = false
	
	# 2. Activate Alert Radius
	alert_radius.monitoring = true
	
	# 3. Wait for one frame to allow physics engine to update overlapping bodies
	await get_tree().physics_frame

	# 4. Scan for allies and collect their names
	var ally_names : Array[String] = []
	
	# WORKAROUND: Area2D detection isn't working, use direct distance check instead
	var all_sentries2 = get_tree().get_nodes_in_group("sentries")
	var alert_range = 2000.0  # Match the AlertRadius collision shape radius
	
	for sentry in all_sentries2:
		if sentry == self: continue
		var distance = global_position.distance_to(sentry.global_position)
		if distance <= alert_range:
			ally_names.append(sentry.name)
	
	# 5. Send allies list back to mind (even if empty)
	Messages.print_message("Found allies: " + str(ally_names), "Sentry")
	network.send_allies_found(ally_names)
	
	# 6. Wait for alert duration, then cleanup
	await get_tree().create_timer(alert_duration).timeout
	end_alert_sequence()

func end_alert_sequence() -> void:
	is_alerting = false
	
	# Reset scanners
	alert_radius.monitoring = false
	alert_radius.scale = Vector2.ONE  # Reset scale
	vision_cone.monitoring = true
	vision_cone.visible = true
	
	# Notify mind that alert sequence is complete
	network.send_signal("alert", "completed", "Alert sequence finished")
	
	# Proceed to cooldown as normal
	start_cooldown()

# --- Cooldown Management ---

func start_cooldown() -> void:
	is_on_cooldown = true
	cooldown_timer.start()
	vision_cone.modulate = Color(0.0, 0.668, 0.372, 0.6) 

func _on_cooldown_timeout() -> void:
	is_on_cooldown = false
	sight_reported = false
	Messages.print_message("Cooldown ended. Scanning resumed.", "Sentry")
	vision_cone.modulate = Color(1.0, 1.0, 1.0, 1.0)
