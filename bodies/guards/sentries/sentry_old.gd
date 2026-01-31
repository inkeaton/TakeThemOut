extends CharacterBody2D

# --- Configuration ---
@export var look_angles : Array[float] = [0.0, 90.0, 180.0, 270.0]
@export var switch_time : float = 2.0
@export var detection_cooldown : float = 5.0 
@export var alert_duration : float = 5.0

# --- State Management ---
enum State { SCANNING, COOLDOWN, ALERT }
var current_state : State = State.SCANNING

var current_look_index : int = 0
var target_player : CharacterBody2D = null

# --- Nodes ---
@onready var vision_cone : Area2D = $VisionCone
@onready var patrol_timer : Timer = $SwitchSide 
# Used for both Cooldown and Alert duration
@onready var state_timer : Timer = $CooldownTimer 
@onready var line_of_sight : RayCast2D = $LineOfSight
@onready var network : VesnaManager = $VesnaManager
# The new ShapeCast node for efficient area scanning
@onready var alert_scanner : ShapeCast2D = $AlertScanner 

# --- Initialization ---

func _ready() -> void:
	patrol_timer.wait_time = switch_time
	patrol_timer.start()
	
	state_timer.one_shot = true 
	state_timer.timeout.connect(_on_state_timer_timeout)
	
	# Ensure scanner checks immediate area and not a vector offset
	alert_scanner.target_position = Vector2.ZERO
	alert_scanner.enabled = false # Keep off to save performance until needed

# --- Logic Flow ---

func _physics_process(_delta: float) -> void:
	# Only run detection logic if we are actively scanning and a potential target is nearby
	if current_state == State.SCANNING and target_player:
		check_line_of_sight()

func _on_patrol_timer_timeout() -> void:
	if current_state == State.SCANNING:
		current_look_index = (current_look_index + 1) % look_angles.size()
		vision_cone.rotation_degrees = look_angles[current_look_index]

# --- Detection Logic ---

func _on_vision_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		target_player = body

func _on_vision_body_exited(body: Node2D) -> void:
	if body == target_player:
		target_player = null

func check_line_of_sight() -> void:
	line_of_sight.target_position = to_local(target_player.global_position)
	line_of_sight.enabled = true
	line_of_sight.force_raycast_update()
	
	if line_of_sight.is_colliding() and line_of_sight.get_collider() == target_player:
		react_to_player()

func react_to_player() -> void:
	Messages.print_message("I SEE YOU! Notifying mind...", "Sentry")
	network.send_sight_with_position("player", 
	target_player.get_instance_id(), target_player.global_position)
	change_state(State.COOLDOWN)

# --- Mind Command Handler ---

func _on_mind_command(intention: Dictionary) -> void:
	var action_type = intention.get("type", "")
	var data = intention.get("data", {})
	
	match action_type:
		"alert":
			if data.get("type", "") == "start":
				trigger_alert_sequence()

# --- State Transitions ---

func change_state(new_state: State) -> void:
	current_state = new_state
	
	match current_state:
		State.SCANNING:
			vision_cone.visible = true
			vision_cone.monitoring = true
			vision_cone.modulate = Color.WHITE
			alert_scanner.enabled = false # Save physics resources
			Messages.print_message("Resuming Patrol.", "Sentry")
			
		State.COOLDOWN:
			vision_cone.modulate = Color(0.0, 0.668, 0.372, 0.6)
			state_timer.start(detection_cooldown)
			
		State.ALERT:
			vision_cone.visible = false
			vision_cone.monitoring = false
			state_timer.start(alert_duration)
			perform_alert_scan()

func _on_state_timer_timeout() -> void:
	if current_state == State.ALERT:
		network.send_signal("alert", "completed", "Alert sequence finished")
	
	# Regardless of previous state, we default back to scanning
	change_state(State.SCANNING)

# --- Alert Specific Logic ---

func trigger_alert_sequence() -> void:
	if current_state == State.ALERT: return
	Messages.print_message("Alert sequence triggered!", "Sentry")
	change_state(State.ALERT)

func perform_alert_scan() -> void:
	# Force an immediate update of the physics shape
	alert_scanner.force_shapecast_update()
	
	var ally_names : Array[String] = []
	
	# Iterate only through actual collisions
	for i in range(alert_scanner.get_collision_count()):
		var body = alert_scanner.get_collider(i)
		
		# Filter: Must be a guard, and must not be self
		if body.is_in_group("guards") and body != self:
			ally_names.append(body.name)
	
	Messages.print_message("Found allies: " + str(ally_names), "Sentry")
	network.send_allies_found(ally_names)
