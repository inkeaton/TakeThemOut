extends CharacterBody2D

# --- Configuration: Movement ---
@export_group("Movement")
@export var speed: float = 100.0
@export var acceleration: float = 100.0
@export var navigation_tolerance: float = 50.0 

# --- Configuration: Tracking ---
@export_group("Tracking")
@export var max_crumbs_to_track: int = 5   # Give up after N crumbs
@export var detection_interval_ms: int = 300 # Vision throttle
@export var chase_path_refresh_interval: float = 0.1 # Chase path throttle

# --- State ---
enum State { PATROLLING, CHASING, TRACKING, INVESTIGATING, IDLE }
var current_state: State = State.PATROLLING

# Investigation State
var investigation_points: Array[Vector2] = []
var investigation_index: int = 0
@export var investigation_radius: float = 400.0

# Navigation State
var current_waypoint_index: int = -1 
var is_moving: bool = false
var sorted_waypoints: Array[Node2D] = []

# Logic State
var target_player: CharacterBody2D = null
var last_detection_time: int = 0
var _chase_cooldown: float = 0.0

# Scent State
var last_crumb_timestamp: int = 0
var crumbs_tracked_count: int = 0 

# --- Nodes ---
@onready var vesna: Node = $VesnaManager
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var vision_cone: Area2D = $VisionCone
@onready var line_of_sight: RayCast2D = $LineOfSight
@onready var scent_cast: ShapeCast2D = $ScentCast
@onready var debug_label: Label = $DebugLabel # <--- Updated Reference

# --- Initialization ---

func _ready() -> void:
	# 1. Optimize Sensor
	# We disable this to prevent it from scanning every frame.
	scent_cast.enabled = false 
	
	# 2. Setup Navigation
	nav_agent.path_desired_distance = 10.0
	nav_agent.target_desired_distance = navigation_tolerance
	
	# Connect signals
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	nav_agent.navigation_finished.connect(_on_navigation_finished)
	
	# 3. Cache Waypoints
	update_debug_label("Initializing...")
	call_deferred("cache_waypoints")

func cache_waypoints() -> void:
	var raw_nodes = get_tree().get_nodes_in_group("waypoints")
	for node in raw_nodes:
		if node is Node2D:
			sorted_waypoints.append(node)
	
	sorted_waypoints.sort_custom(func(a, b): return a.name < b.name)
	Messages.print_message("Patrol initialized with %d waypoints." % sorted_waypoints.size(), "PatrolBody")
	
	if not sorted_waypoints.is_empty():
		update_debug_label("Ready (Patrol)")
	else:
		update_debug_label("Ready (No Waypoints)")

# --- Helper ---

func update_debug_label(text: String) -> void:
	if debug_label:
		debug_label.text = text

# --- Command Handling (Vesna) ---

func _on_vesna_manager_command_received(command: Dictionary) -> void:
	var type = command.get("type", "")
	var data = command.get("data", {})
	
	match type:
		# UNIFIED COMMAND: "patrol" handles all movement logic
		"patrol":
			var action = data.get("action", "")
			match action:
				"next":
					move_cyclic(1)
				"prev":
					move_cyclic(-1)
				"resume":
					# Waking up from IDLE
					current_state = State.PATROLLING
					move_cyclic(1)
					update_debug_label("Resuming Patrol (Mind Order)")
					Messages.print_message("Resuming Patrol (Mind Order).", "Patrol")
					
		"chase":
			if data.get("type", "") == "start":
				# Extract patience from the command, defaulting to 5 if missing
				var new_patience = data.get("patience", 5)
				
				# Apply it to our tracking variable
				max_crumbs_to_track = int(new_patience)
				Messages.print_message("Chase started with Patience: %d" % max_crumbs_to_track, "Patrol")
				
				trigger_chase_sequence()
		
		"investigate":
			var points = data.get("points", 3)
			current_state = State.INVESTIGATING
			generate_investigation_points(int(points))
			# Start moving to the first point immediately
			is_moving = true
			update_debug_label("Starting Investigation...")

func move_cyclic(direction: int) -> void:
	if sorted_waypoints.is_empty(): return

	current_waypoint_index = (current_waypoint_index + direction) % sorted_waypoints.size()
	if current_waypoint_index < 0:
		current_waypoint_index += sorted_waypoints.size()
	
	var target_node = sorted_waypoints[current_waypoint_index]
	
	update_debug_label("Patrolling: %s" % target_node.name)
	Messages.print_message("Moving to index %d (%s)" % [current_waypoint_index, target_node.name], "PatrolBody")
	
	nav_agent.target_position = target_node.global_position
	is_moving = true

# --- Physics & Logic Loop ---

func _physics_process(delta: float) -> void:
	# 1. State Logic
	match current_state:
		State.CHASING:
			_process_chase_logic(delta)
		State.TRACKING:
			_process_tracking_logic()
		State.INVESTIGATING:
			_process_investigation_logic()

	# 2. Vision Rotation
	if velocity.length() > 0.1:
		vision_cone.rotation = velocity.angle()
		
	# 3. Vision Check
	if target_player:
		check_line_of_sight()

	# 4. Movement Execution
	if nav_agent.is_navigation_finished():
		_on_velocity_computed(Vector2.ZERO) # Decelerate to stop
		return

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

# --- Logic: Chase ---

func trigger_chase_sequence() -> void:
	if target_player == null: return
	current_state = State.CHASING
	is_moving = true 
	nav_agent.target_position = target_player.global_position
	update_debug_label("CHASING PLAYER!")
	Messages.print_message("STARTING to Chase PLAYER", "Patrol")

func _process_chase_logic(delta: float) -> void:
	if target_player == null: return
		
	_chase_cooldown -= delta
	if _chase_cooldown <= 0:
		nav_agent.target_position = target_player.global_position
		_chase_cooldown = chase_path_refresh_interval

# --- Logic: Tracking (Scent) ---

func _process_tracking_logic() -> void:
	if not nav_agent.is_navigation_finished():
		return

	# MANUAL ACTIVATION
	scent_cast.force_shapecast_update()

	# FAILURE CASE 1: Trail Cold
	if not scent_cast.is_colliding():
		update_debug_label("Trail Cold. Waiting...")
		Messages.print_message("Trail cold. Reporting to Mind...", "Patrol")
		_enter_idle_state("cold_trail")
		return

	# Process Results...
	var best_crumb: Crumb = null
	var best_timestamp: int = -1

	for i in scent_cast.get_collision_count():
		var collider = scent_cast.get_collider(i)
		if not collider is Crumb: continue
			
		if collider.timestamp > last_crumb_timestamp:
			if collider.timestamp > best_timestamp:
				best_timestamp = collider.timestamp
				best_crumb = collider
	
	if best_crumb:
		crumbs_tracked_count += 1
		
		# FAILURE CASE 2: Patience Limit
		if crumbs_tracked_count > max_crumbs_to_track:
			update_debug_label("Patience Lost. Waiting...")
			Messages.print_message("Patience limit (%d). Reporting to Mind..." % crumbs_tracked_count, "Patrol")
			_enter_idle_state("patience_limit")
			return

		nav_agent.target_position = best_crumb.global_position
		last_crumb_timestamp = best_timestamp
		
		update_debug_label("Tracking: Crumb %d/%d" % [crumbs_tracked_count, max_crumbs_to_track])
		Messages.print_message("Tracking crumb %d..." % crumbs_tracked_count, "Patrol")
	else:
		# FAILURE CASE 3: End of Line (Old crumbs only)
		update_debug_label("End of Trail. Waiting...")
		Messages.print_message("End of trail. Reporting to Mind...", "Patrol")
		_enter_idle_state("end_of_trail")
	
func _enter_idle_state(reason: String) -> void:
	current_state = State.IDLE
	is_moving = false
	velocity = Vector2.ZERO
	update_debug_label("IDLE (Mind Querying)")
	
	# Send the report
	vesna.send_target_lost(global_position, reason)

# --- Navigation & Events ---

func _on_navigation_finished() -> void:
	if current_state == State.TRACKING: return # Tracking logic handles its own arrival
	if not is_moving: return
	
	is_moving = false
	velocity = Vector2.ZERO
	Messages.print_message("Reached waypoint %d" % current_waypoint_index, "PatrolBody")
	vesna.send_navigation_update("reached", "%d" % current_waypoint_index)

# --- Vision Events ---

func _on_vision_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		target_player = body

func _on_vision_body_exited(body: Node2D) -> void:
	if body == target_player:
		target_player = null
		
		# State Transition: Chase -> Tracking
		if current_state == State.CHASING:
			current_state = State.TRACKING
			last_crumb_timestamp = 0 
			crumbs_tracked_count = 0
			
			update_debug_label("Lost Visual. Sniffing...")
			Messages.print_message("Visual lost! Switching to Tracking.", "Patrol")

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
	if current_state == State.TRACKING or current_state == State.INVESTIGATING:
		current_state = State.CHASING
		update_debug_label("CHASING PLAYER!")
		
	Messages.print_message("I SEE YOU! Notifying mind...", "Patrol")
	vesna.send_sight_with_position("player", 
	target_player.get_instance_id(), target_player.global_position)

# --- Investigating ---

func generate_investigation_points(count: int) -> void:
	investigation_points.clear()
	investigation_index = 0
	
	# Get the Navigation Map RID (required to query the server directly)
	var map_rid = nav_agent.get_navigation_map()
	
	for i in range(count):
		# 1. Pick a random point in a circle
		var random_offset = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(100.0, investigation_radius)
		var target_pos = global_position + random_offset
		
		# 2. Snap it to the nearest valid point on the Navigation Mesh
		# This ensures we don't try to walk into walls or void
		var valid_pos = NavigationServer2D.map_get_closest_point(map_rid, target_pos)
		
		investigation_points.append(valid_pos)
	
	Messages.print_message("Generated %d investigation points." % investigation_points.size(), "Patrol")

# --- Logic: Investigation ---
func _process_investigation_logic() -> void:
	# Wait until we arrive at the current point
	if not nav_agent.is_navigation_finished():
		return
		
	# Are there more points to visit?
	if investigation_index < investigation_points.size():
		var next_point = investigation_points[investigation_index]
		nav_agent.target_position = next_point
		
		update_debug_label("Investigating: %d/%d" % [investigation_index + 1, investigation_points.size()])
		Messages.print_message("Investigating point %d/%d" % [investigation_index + 1, investigation_points.size()], "Patrol")
		investigation_index += 1
	else:
		# We are done
		update_debug_label("Investigation Done. Waiting...")
		Messages.print_message("Investigation complete. Reporting to Mind.", "Patrol")
		
		# Enter IDLE to wait for orders
		current_state = State.IDLE
		is_moving = false
		
		# Send standard event format: type(status, reason)
		vesna.send_event("investigation", {
			"status": "complete",
			"reason": "points_finished"
		})
