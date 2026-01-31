extends CharacterBody2D

# --- Configuration ---
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
	
	# The Puppet decides WHICH state handles the command
	match type:
		"patrol":
			# Switch to Patrol State (if not already) and pass the data
			state_machine.change_state_by_name("Patrol", data)
			
		"chase":
			if data.get("type", "") == "start":
				state_machine.change_state_by_name("Chase", data)
				
		"investigate":
			state_machine.change_state_by_name("Investigate", data)
		
		"move_to":
			state_machine.change_state_by_name("Travel", data)

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
			state_machine.change_state_by_name("Track")

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
