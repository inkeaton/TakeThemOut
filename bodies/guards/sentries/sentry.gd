## SentryBody: Executes sentry sensing logic and mind-commanded state transitions.
extends CharacterBody2D

# --- Configuration ---
@export_group("Sentry Settings")
@export var look_angles: Array[float] = [0.0, 90.0, 180.0, 270.0]
@export var detection_interval_ms: int = 200

# --- State ---
var target_player: CharacterBody2D = null
var last_detection_time: int = 0
var current_look_index: int = 0

# --- Nodes ---
@onready var state_machine: StateMachine = $StateMachine
@onready var vesna: VesnaManager = $VesnaManager
@onready var vision_cone: Area2D = $VisionCone
@onready var line_of_sight: RayCast2D = $LineOfSight
@onready var alert_scanner: ShapeCast2D = $AlertScanner
@onready var sprite: Sprite2D = $Sprite
@onready var debug_label: Label = $DebugLabel

# --- Lifecycle ---
func _ready() -> void:
	# 1. Setup Scanner (Ensure it is off by default)
	alert_scanner.enabled = false
	alert_scanner.target_position = Vector2.ZERO
	
	# 2. Initialize brain
	state_machine.init(self, null, vesna) # Sentry has no NavigationAgent, pass null

# --- Physics Loop ---

func _physics_process(delta: float) -> void:
	# 1. Vision Check (Global)
	# Runs regardless of state, but we throttle it for performance
	if target_player:
		check_line_of_sight()
		
	# 2. State Logic
	state_machine._physics_process(delta)

# --- Core Helpers ---

func rotate_viewpoint() -> void:
	current_look_index = (current_look_index + 1) % look_angles.size()
	var new_angle = look_angles[current_look_index]
	vision_cone.rotation_degrees = new_angle
	
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
	# Prevention: Don't spam if already reacting or alerting
	if state_machine.current_state.name == "Scan":
		Messages.print_message("I SEE YOU! Notifying mind...", "Sentry")
		
		# Send data
		vesna.send_sight_with_position("player", 
		target_player.get_instance_id(), target_player.global_position)
		
		# Transition to idle and wait for explicit mind instructions.
		state_machine.change_state_by_name("Idle")

# --- Command Handling ---

func _on_vesna_mind_command(intention: Dictionary) -> void:
	var action_type = intention.get("type", "")
	var data = intention.get("data", {})
	
	match action_type:
		"transition_to":
			_handle_transition_to(data)
		"set_var":
			_handle_set_var(data)

## Handles the transition_to command from the mind.
func _handle_transition_to(data: Dictionary) -> void:
	var target_state = data.get("target_state", "")
	var params = data.get("params", {})
	
	if target_state.is_empty():
		push_warning("transition_to: Empty target state")
		return
	
	Messages.print_message("Mind orders: Transition to %s" % target_state, "Sentry")
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
		Messages.print_message("Set %s = %s" % [var_name, str(var_value)], "Sentry")
		return
	
	# Try to set on state machine states
	for state in state_machine.states.values():
		if var_name in state:
			state.set(var_name, var_value)
			Messages.print_message("Set %s.%s = %s" % [state.name, var_name, str(var_value)], "Sentry")
			return
	
	push_warning("set_var: Variable '%s' not found in sentry or states" % var_name)

# --- Signals ---

func _on_vision_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		target_player = body

func _on_vision_body_exited(body: Node2D) -> void:
	if body == target_player:
		target_player = null

func update_debug_label(text: String) -> void:
	if debug_label:
		debug_label.text = text
