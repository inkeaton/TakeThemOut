extends CharacterBody2D

# --- Configuration ---
const SPEED = 150.0
const ACCELERATION = 30.0
const ROTATION_SPEED = 10.0

# --- State ---
enum State { IDLE, PATROLLING, CHASING, SEARCHING }
var current_state = State.IDLE

var chase_target: Node2D = null
var is_seeing_target: bool = false
var last_known_pos: Vector2 = Vector2.ZERO
var waypoint_reached: bool = false  # Flag to prevent multiple completion signals

# --- Nodes ---
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var vision_cone: Area2D = $VisionCone
@onready var patience_timer: Timer = $PatienceTimer
@onready var network: VesnaManager = $VesnaManager
@onready var debug_label: Label = $DebugLabel 

func _ready() -> void:
	# Setup Navigation
	nav_agent.path_desired_distance = 10.0
	nav_agent.target_desired_distance = 10.0
	
	# Setup Vision
	vision_cone.body_entered.connect(_on_vision_body_entered)
	vision_cone.body_exited.connect(_on_vision_body_exited)
	patience_timer.timeout.connect(_on_patience_timeout)
	
	update_debug_label()

func _physics_process(delta: float) -> void:
	# 1. Update Target Logic (The "Eyes")
	if current_state == State.CHASING:
		if is_seeing_target and chase_target:
			# Live tracking: Keep updating target to player's current spot
			nav_agent.target_position = chase_target.global_position
			last_known_pos = chase_target.global_position
		else:
			# Blind tracking: Target remains fixed at 'last_known_pos'
			# (NavigationAgent automatically keeps the old target_position)
			pass

	# 2. Movement Logic (The "Legs")
	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		
		# Special Logic: Arrived at destination?
		if current_state == State.CHASING:
			_on_lkp_reached()
		elif current_state == State.PATROLLING and not waypoint_reached:
			# Notify mind that waypoint was reached (only once)
			waypoint_reached = true
			network.send_signal("movement", "completed", "waypoint_reached")
			
	else:
		# Navigation in progress - reset waypoint flag
		waypoint_reached = false
		
		var next_path_pos = nav_agent.get_next_path_position()
		var direction = (next_path_pos - global_position).normalized()
		
		# Move
		velocity = velocity.lerp(direction * SPEED, ACCELERATION * delta)
		
		# Rotate Vision Cone to face movement
		if velocity.length() > 10.0:
			var target_angle = velocity.angle()
			vision_cone.rotation = lerp_angle(vision_cone.rotation, target_angle, ROTATION_SPEED * delta)

	move_and_slide()

# --- Network Command Handling ---

func _on_vesna_manager_command_received(intention: Dictionary) -> void:
	var type = intention.get("type", "")
	var data = intention.get("data", {})
	
	match type:
		"walk":
			if data.get("type") == "goto":
				_start_patrol(data.get("target"))
		"chase":
			_start_chase(data.get("id"))
		"stop":
			_stop_moving()

func _start_patrol(target_name: String) -> void:
	var waypoint_path = "/root/test_maze/waypoints/" + target_name
	Messages.print_message("Looking for waypoint at: " + waypoint_path, name)
	var target_node = get_node_or_null(waypoint_path)
	if target_node:
		current_state = State.PATROLLING
		waypoint_reached = false  # Reset flag for new waypoint
		nav_agent.target_position = target_node.global_position
		debug_label.text = "Patrolling to " + target_name
		Messages.print_message("Navigating to position: " + str(target_node.global_position), name)
	else:
		Warnings.print_warning("Waypoint not found at: " + waypoint_path, name)
		network.send_signal("movement", "failed", "waypoint_not_found")


func _start_chase(target_id: int) -> void:
	var target = instance_from_id(target_id)
	if target and target is Node2D:
		current_state = State.CHASING
		chase_target = target
		# Check if we actually see the target - don't assume visibility
		is_seeing_target = vision_cone.has_overlapping_bodies() and vision_cone.get_overlapping_bodies().has(target)
		if not is_seeing_target:
			# Player already lost before chase started, start patience timer immediately
			patience_timer.start()
			Messages.print_message("Chase started but player already lost", name)
		nav_agent.target_position = target.global_position
		debug_label.text = "CHASING!"

func _stop_moving() -> void:
	current_state = State.IDLE
	nav_agent.target_position = global_position # Clears path
	velocity = Vector2.ZERO
	debug_label.text = "Idle"

# --- Vision & LKP Logic ---

func _on_vision_body_entered(body: Node2D) -> void:
	if body.name == "Player": # Or check group/class
		is_seeing_target = true
		patience_timer.stop()
		
		# Visual feedback
		vision_cone.modulate = Color(1, 0, 0, 0.5) # Red
		
		# Notify Mind immediately
		network.send_sight("player", body.get_instance_id())

func _on_vision_body_exited(body: Node2D) -> void:
	if body.name == "Player":
		is_seeing_target = false
		if current_state == State.CHASING:
			# Don't give up yet! Start the "Patience" timer
			patience_timer.start()
			debug_label.text = "Lost Sight... Moving to LKP"
		else:
			# Even if not chasing, notify mind immediately so it knows player is lost
			network.send_signal("sight", "lost", "visual_contact_broken_before_chase")
			vision_cone.modulate = Color(1, 1, 1, 0.5) # Reset color

func _on_patience_timeout() -> void:
	# Timer ran out -> Player is truly gone
	if current_state == State.CHASING:
		network.send_signal("sight", "lost", "visual_contact_broken")
		vision_cone.modulate = Color(1, 1, 0, 0.5) # Yellow (Searching)

func _on_lkp_reached() -> void:
	# We arrived at the ghost position and still see nothing
	current_state = State.SEARCHING
	debug_label.text = "LKP Reached. Searching."
	network.send_signal("movement", "completed", "lkp_reached")

# --- Debugging ---
func update_debug_label():
	# Optional helper if we want complex debug text
	pass
