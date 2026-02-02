extends CharacterBody2D

# --- Configuration ---
@export_group("Movement")
@export var speed: float = 100.0
@export var acceleration: float = 100.0
@export var navigation_tolerance: float = 50.0 

@export_group("Vision")
@export var detection_interval_ms: int = 300

@export_group("Alert Lock")
@export var alert_lock_timeout_ms: int = 60000  # 60 second failsafe timeout

# --- Shared State (Context) ---
# These are accessed by the individual States
var target_player: CharacterBody2D = null
var is_moving: bool = false
var last_detection_time: int = 0

# --- Alert Lock State ---
# When true, patrol commands are ignored and navigation signals are suppressed
var alert_lock: bool = false
var _alert_lock_start_time: int = 0

# --- Nodes ---
@onready var state_machine: StateMachine = $StateMachine
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var vesna: VesnaManager = $VesnaManager
@onready var vision_cone: Area2D = $VisionCone
@onready var line_of_sight: RayCast2D = $LineOfSight
@onready var debug_label: Label = $DebugLabel
# ScentCast is now accessed directly by TrackState via Unique Name, 
# or we can keep a reference here if preferred.
@onready var scent_cast: ShapeCast2D = $ScentCast
@onready var ally_scanner: ShapeCast2D = $AllyScanner

# --- Ally Scanning Configuration ---
@export_group("Ally Scanning")
@export var ally_scan_interval_ms: int = 1500
var _last_ally_scan_time: int = 0

func _ready() -> void:
	# 1. Setup Navigation
	nav_agent.path_desired_distance = 10.0
	nav_agent.target_desired_distance = navigation_tolerance
	
	# Connect signals
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	
	# 2. Initialize Brain
	# Pass "self" so states can access our variables
	state_machine.init(self, nav_agent, vesna)
	
	update_debug_label("Initialized")

# --- Physics Loop ---

func _physics_process(delta: float) -> void:
	# 0. Alert Lock Timeout Failsafe
	# Prevents permanent stuck state if mind fails to unlock
	if alert_lock:
		var elapsed = Time.get_ticks_msec() - _alert_lock_start_time
		if elapsed > alert_lock_timeout_ms:
			Messages.print_message("Alert lock timeout! Auto-unlocking after %ds" % (elapsed / 1000), "Patrol")
			_release_alert_lock()
	
	# 1. Vision Check (Global priority)
	# This runs regardless of state.
	if target_player:
		check_line_of_sight()
		
	# 2. Vision Rotation
	if velocity.length() > 0.1:
		vision_cone.rotation = velocity.angle()

	# 3. State Logic
	# The current state calculates where we should go
	state_machine._physics_process(delta)

	# 4. Physics Application
	# If the State wants to move, it sets nav_agent.target_position.
	# We handle the actual sliding here.
	if nav_agent.is_navigation_finished():
		_on_velocity_computed(Vector2.ZERO)
	else:
		var next_path_pos: Vector2 = nav_agent.get_next_path_position()
		var desired_velocity: Vector2 = global_position.direction_to(next_path_pos) * speed
		
		if nav_agent.avoidance_enabled:
			nav_agent.set_velocity(desired_velocity)
		else:
			_on_velocity_computed(desired_velocity)

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	var current_delta = get_physics_process_delta_time()
	velocity = velocity.move_toward(safe_velocity, acceleration * current_delta)
	move_and_slide()

# --- Command Handling ---

func _on_vesna_manager_command_received(command: Dictionary) -> void:
	var type = command.get("type", "")
	var data = command.get("data", {})
	
	# Handle lock and set_var first (they don't change state)
	match type:
		"lock":
			_handle_lock(data)
			return
		
		"set_var":
			_handle_set_var(data)
			return
	
	# Check alert_lock for patrol commands only
	if type == "patrol" and alert_lock:
		Messages.print_message("Ignoring patrol command during alert lock", "Patrol")
		return
	
	# State-changing commands
	match type:
		"patrol":
			state_machine.change_state_by_name("Patrol", data)
			
		"chase":
			# Chase sets alert lock (we're pursuing)
			if data.get("type", "") == "start":
				_set_alert_lock()
				state_machine.change_state_by_name("Chase", data)
				
		"investigate":
			state_machine.change_state_by_name("Investigate", data)
		
		"move_to":
			# move_to sets alert lock (responding to alert)
			_set_alert_lock()
			state_machine.change_state_by_name("Travel", data)

## Handles lock command - sets or releases alert lock.
func _handle_lock(data: Dictionary) -> void:
	var action = data.get("action", "")
	
	match action:
		"set":
			nav_agent.target_position = global_position
			is_moving = false
			velocity = Vector2.ZERO
			_set_alert_lock()
			Messages.print_message("Stopped. Alert lock engaged.", "Patrol")
		
		"release":
			_release_alert_lock()
			Messages.print_message("Alert lock released.", "Patrol")
		
		_:
			push_warning("lock: Unknown action '%s'" % action)

## Sets alert lock with timestamp for timeout tracking.
func _set_alert_lock() -> void:
	if not alert_lock:
		alert_lock = true
		_alert_lock_start_time = Time.get_ticks_msec()

## Releases alert lock.
func _release_alert_lock() -> void:
	alert_lock = false
	_alert_lock_start_time = 0

## Handles the set_var command from the mind.
## Searches for the variable in self, then in child states.
func _handle_set_var(data: Dictionary) -> void:
	var var_name = data.get("name", "")
	var var_value = data.get("value")
	
	if var_name.is_empty():
		push_warning("set_var: Empty variable name received")
		return
	
	# Try to set on self first
	if var_name in self:
		set(var_name, var_value)
		Messages.print_message("Set %s = %s" % [var_name, str(var_value)], "Patrol")
		return
	
	# Try to set on state machine states
	for state in state_machine.states.values():
		if var_name in state:
			state.set(var_name, var_value)
			Messages.print_message("Set %s.%s = %s" % [state.name, var_name, str(var_value)], "Patrol")
			return
	
	push_warning("set_var: Variable '%s' not found in patrol or states" % var_name)

# --- Shared Vision Logic ---

func _on_vision_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		target_player = body

func _on_vision_body_exited(body: Node2D) -> void:
	if body == target_player:
		target_player = null
		
		# Global Transition Rule: 
		# If we lose sight while Chasing, go to Tracking
		if state_machine.current_state.name == "Chase":
			# Get patience from Chase state and pass it to Track
			var chase_state = state_machine.current_state
			var patience_msg = {"patience": chase_state.stored_patience}
			state_machine.change_state_by_name("Track", patience_msg)

func check_line_of_sight() -> void:
	var current_time = Time.get_ticks_msec()
	if current_time - last_detection_time < detection_interval_ms:
		return
	last_detection_time = current_time
	
	line_of_sight.target_position = to_local(target_player.global_position)
	line_of_sight.enabled = true
	line_of_sight.force_raycast_update()
	
	if line_of_sight.is_colliding() and line_of_sight.get_collider() == target_player:
		react_to_player()
	line_of_sight.enabled = false

func react_to_player() -> void:
	# Global Transition Rule: 
	# If we see player, ALWAYS Chase (unless Mind overrides later)
	if state_machine.current_state.name != "Chase":
		state_machine.change_state_by_name("Chase")
		
	Messages.print_message("I SEE YOU!", "Patrol")
	vesna.send_sight_with_position("player", 
	target_player.get_instance_id(), target_player.global_position)

func update_debug_label(text: String) -> void:
	if debug_label:
		debug_label.text = text

# --- Ally Scanning (for chase coordination) ---

## Scans for nearby patrol allies during chase/track to coordinate pursuit.
## Uses throttling to avoid performance impact.
## Only reports patrols NOT already in Chase/Track state (recruits idle patrols).
func scan_for_chase_allies() -> void:
	# Throttle check
	var current_time = Time.get_ticks_msec()
	if current_time - _last_ally_scan_time < ally_scan_interval_ms:
		return
	_last_ally_scan_time = current_time
	
	# Perform the scan
	ally_scanner.force_shapecast_update()
	
	if not ally_scanner.is_colliding():
		return
	
	# Collect patrol allies that are NOT already chasing
	var ally_names: Array[String] = []
	for i in range(ally_scanner.get_collision_count()):
		var collider = ally_scanner.get_collider(i)
		
		# Skip self
		if collider == self:
			continue
		
		# Only detect other patrols (not sentries, captains, etc.)
		if not collider.is_in_group("patrols"):
			continue
		
		# Only recruit patrols NOT already in Chase/Track state
		# (they're available to help)
		if collider.has_node("StateMachine"):
			var their_state = collider.get_node("StateMachine").current_state
			if their_state and their_state.name in ["Chase", "Track"]:
				continue  # They're already chasing, skip
		
		ally_names.append(collider.name)
	
	# Report to mind if we found available allies
	if not ally_names.is_empty():
		Messages.print_message("Found available patrol allies: %s" % str(ally_names), "Patrol")
		vesna.send_allies_found(ally_names)
