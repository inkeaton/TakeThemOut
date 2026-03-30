extends CharacterBody2D

# --- Configuration ---
@export_group("Identity")
## Name used in the chat system (e.g. "susanna", "rosanna")
@export var personality_name: String = ""

@export_group("Movement")
@export var speed: float = 100.0
@export var acceleration: float = 100.0
@export var navigation_tolerance: float = 50.0 

@export_group("Vision")
@export var detection_interval_ms: int = 300

# --- Shared State (Context) ---
# These are accessed by the individual States
var target_player: CharacterBody2D = null
var is_moving: bool = false
var last_detection_time: int = 0

# --- Chase State ---
# When true, patrol is in Chase/Track mode - some commands may be blocked
var is_chasing: bool = false

# --- Messenger State ---
# When true, patrol is acting as a messenger to inform captain
var is_messenger: bool = false

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
@onready var hand: Area2D = $Hand

# --- Ally Scanning Configuration ---
@export_group("Ally Scanning")
@export var ally_scan_interval_ms: int = 1500
var _last_ally_scan_time: int = 0

func _ready() -> void:
	# 1. Setup Navigation
	nav_agent.path_desired_distance = 10.0
	nav_agent.target_desired_distance = navigation_tolerance
	nav_agent.max_speed = speed
	
	# Connect signals
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	
	# 2. Connect Hand (catching) Area2D
	hand.body_entered.connect(_on_hand_body_entered)
	
	# 3. Initialize Brain
	# Pass "self" so states can access our variables
	state_machine.init(self, nav_agent, vesna)
	
	update_debug_label("Initialized")

# --- Catching Mechanic ---

## When the player physically touches the guard's Hand area, trigger an encounter.
## Only catches during active pursuit (Chase/Track states).
func _on_hand_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	
	# Only catch if actively pursuing
	if not is_chasing:
		return
	
	var chat_name = personality_name if personality_name != "" else name
	Messages.print_message("CAUGHT the player! Triggering encounter as '%s'" % chat_name, "Patrol")
	get_tree().current_scene.trigger_encounter(chat_name)

# --- Physics Loop ---

func _physics_process(delta: float) -> void:
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
	
	# Handle set_var (doesn't change state)
	if type == "set_var":
		_handle_set_var(data)
		return
	
	# Handle transition_to (primary command)
	if type == "transition_to":
		_handle_transition_to(data)
		return

## Handles the transition_to command from the mind.
func _handle_transition_to(data: Dictionary) -> void:
	var target_state = data.get("target_state", "")
	var params = data.get("params", {})
	
	if target_state.is_empty():
		push_warning("transition_to: Empty target state")
		return
	
	# Block non-Chase transitions if currently chasing (Chase has priority)
	if is_chasing and target_state not in ["Chase", "Track"]:
		Messages.print_message("Ignoring %s transition while chasing" % target_state, "Patrol")
		return
	
	# Set is_chasing for Chase state
	if target_state == "Chase":
		is_chasing = true
	
	Messages.print_message("Mind orders: Transition to %s" % target_state, "Patrol")
	state_machine.change_state_by_name(target_state, params)

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

# --- Captain Discovery (for messenger coordination) ---

## Finds the nearest captain by searching the scene tree.
## Returns the name of the closest captain, or empty string if none found.
func find_nearest_captain() -> String:
	var captains = get_tree().get_nodes_in_group("captains")
	
	if captains.is_empty():
		return ""
	
	var nearest_captain: Node2D = null
	var nearest_distance: float = INF
	
	for captain in captains:
		if not captain is Node2D:
			continue
		
		var dist = global_position.distance_to(captain.global_position)
		if dist < nearest_distance:
			nearest_distance = dist
			nearest_captain = captain
	
	if nearest_captain:
		Messages.print_message("Nearest captain: %s (%.1f units)" % [nearest_captain.name, nearest_distance], "Patrol")
		return nearest_captain.name
	
	return ""
