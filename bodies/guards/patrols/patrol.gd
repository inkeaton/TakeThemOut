extends CharacterBody2D

# --- Configuration ---
@export var speed : float = 80.0
@export var navigation_tolerance : float = 50.0 

# --- State ---
var current_waypoint_index : int = -1 # Start at -1 so first "next" goes to 0
var is_moving : bool = false
# Ordered list of marker nodes
var sorted_waypoints : Array[Node2D] = []

# --- Nodes ---
@onready var nav_agent : NavigationAgent2D = $NavigationAgent2D
@onready var vesna : Node = $VesnaManager

# --- Initialization ---

func _ready() -> void:
	# 1. Setup Navigation
	nav_agent.path_desired_distance = 10.0
	nav_agent.target_desired_distance = navigation_tolerance
	
	# Important: Connect velocity computed for obstacle avoidance
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	nav_agent.navigation_finished.connect(_on_navigation_finished)
	
	# 2. Cache and Sort Waypoints
	call_deferred("cache_waypoints")

func cache_waypoints() -> void:
	# Find all nodes in group "waypoints"
	var raw_nodes = get_tree().get_nodes_in_group("waypoints")
	
	# Filter only Node2D types (Markers/Position2D)
	for node in raw_nodes:
		if node is Node2D:
			sorted_waypoints.append(node)
	
	# SORT alphabetically so m1_a comes before m1_b
	sorted_waypoints.sort_custom(func(a, b): return a.name < b.name)
	
	Messages.print_message("Patrol initialized with %d waypoints." % sorted_waypoints.size(), "PatrolBody")

# --- Command Handling ---

# Handles both "next" and "prev"
func move_cyclic(direction: int) -> void:
	if sorted_waypoints.is_empty():
		return

	# Calculate new index
	# (index + 1) for next, (index - 1) for prev
	current_waypoint_index = (current_waypoint_index + direction) % sorted_waypoints.size()
	
	# GDScript modulo can return negative numbers (e.g., -1 % 5 = -1). 
	# We need it to wrap around to the end (4).
	if current_waypoint_index < 0:
		current_waypoint_index += sorted_waypoints.size()
	
	var target_node = sorted_waypoints[current_waypoint_index]
	
	Messages.print_message("Moving to index %d (%s)" % [current_waypoint_index, target_node.name], "PatrolBody")
	
	nav_agent.target_position = target_node.global_position
	is_moving = true

# Update command handle
func _on_vesna_manager_command_received(command: Dictionary) -> void:
	var type = command.get("type", "")
	var data = command.get("data", {})
	
	match type:
		"move":
			var action = data.get("action", "")
			if action == "next":
				move_cyclic(1)
			elif action == "prev": # NEW
				move_cyclic(-1)

# --- Physics & Movement ---

func _physics_process(_delta: float) -> void:
	if not is_moving:
		update_animation(Vector2.ZERO)
		return

	# If navigation is finished, do nothing (wait for signal to fire)
	if nav_agent.is_navigation_finished():
		return

	var next_path_position : Vector2 = nav_agent.get_next_path_position()
	var current_position : Vector2 = global_position
	
	# Compute velocity towards next path point
	var new_velocity : Vector2 = current_position.direction_to(next_path_position) * speed
	
	# Trigger avoidance calculation
	if nav_agent.avoidance_enabled:
		nav_agent.set_velocity(new_velocity)
	else:
		_on_velocity_computed(new_velocity)

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()
	update_animation(velocity)

# --- Navigation Events ---

func _on_navigation_finished() -> void:
	if not is_moving: return
	
	is_moving = false
	velocity = Vector2.ZERO
	update_animation(Vector2.ZERO)
	
	Messages.print_message("Arrived at waypoint index %d" % current_waypoint_index, "PatrolBody")
	
	# Notify the Mind
	# NEW CALL: Send dedicated navigation message
	vesna.send_navigation_update("reached", "%d" % current_waypoint_index)

# --- Visuals ---

func update_animation(vel: Vector2) -> void:
	pass
	#if vel.length() > 0.1:
		#animation_player.play("walk_down")
		## Flip sprite if moving left
		#if sprite: sprite.flip_h = vel.x < 0
	#else:
		#animation_player.play("RESET")
