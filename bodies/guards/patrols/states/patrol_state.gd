extends State

## Patrol state: Handles both waypoint navigation and coordinate navigation.
## Unified from previous Patrol + Travel states.
## On arrival, transitions to Idle and notifies mind.

## Export variable for assigning specific waypoint zones to this agent
## Supports multiple parent nodes - waypoints from all parents will be combined
## Leave empty to use all waypoints from the global "waypoints" group (backward compatibility)
@export var waypoint_parents: Array[NodePath] = []

var current_waypoint_index: int = -1 
var sorted_waypoints: Array[Node2D] = []

## Tracks whether we're navigating to coords (true) or waypoint (false)
var _navigating_to_coords: bool = false
var _target_coords: Vector2 = Vector2.ZERO

func enter(msg: Dictionary = {}) -> void:
	# If this is the first run, cache waypoints
	if sorted_waypoints.is_empty():
		_cache_waypoints()
	
	# Handle target parameter (new unified system)
	if msg.has("target"):
		_handle_target(msg["target"])
	# Legacy: Handle action parameter for backward compatibility
	elif msg.has("action"):
		_handle_action(msg["action"])
	else:
		body.update_debug_label("Patrolling")

func _cache_waypoints() -> void:
	# Option 1: Use assigned waypoint parent nodes (multiple zones supported)
	if not waypoint_parents.is_empty():
		for parent_path in waypoint_parents:
			if parent_path.is_empty():
				continue
			
			var parent_node = get_node_or_null(parent_path)
			if parent_node == null:
				push_warning("Waypoint parent not found: %s" % parent_path)
				continue
			
			# Collect all Node2D children from this parent
			for child in parent_node.get_children():
				if child is Node2D:
					sorted_waypoints.append(child)
		
		if sorted_waypoints.is_empty():
			push_warning("No waypoints found in assigned parent nodes. Falling back to global 'waypoints' group.")
		else:
			sorted_waypoints.sort_custom(func(a, b): return a.name < b.name)
			Messages.print_message("Cached %d waypoints from %d zone(s)" % [sorted_waypoints.size(), waypoint_parents.size()], "Patrol")
			return
	
	# Option 2: Fallback to global "waypoints" group (backward compatibility)
	var raw_nodes = get_tree().get_nodes_in_group("waypoints")
	for node in raw_nodes:
		if node is Node2D:
			sorted_waypoints.append(node)
	sorted_waypoints.sort_custom(func(a, b): return a.name < b.name)
	
	if sorted_waypoints.is_empty():
		push_warning("No waypoints found! Agent will not patrol.")
	else:
		Messages.print_message("Cached %d waypoints from global group" % sorted_waypoints.size(), "Patrol")

func _handle_action(action: String) -> void:
	_navigating_to_coords = false  # Waypoint navigation
	match action:
		"next":
			move_cyclic(1)
		"prev":
			move_cyclic(-1)
		"resume":
			body.update_debug_label("Resuming Patrol")
			move_cyclic(1)
		"random":
			if sorted_waypoints.is_empty(): return
			
			# Pick a random index distinct from the current one (optional polish)
			var new_index = randi() % sorted_waypoints.size()
			while sorted_waypoints.size() > 1 and new_index == current_waypoint_index:
				new_index = randi() % sorted_waypoints.size()
			
			current_waypoint_index = new_index
			var target_node = sorted_waypoints[current_waypoint_index]
			
			body.update_debug_label("Patrol: Random (%s)" % target_node.name)
			Messages.print_message("Moving to random waypoint %s" % target_node.name, "Patrol")
			
			nav_agent.target_position = target_node.global_position
			body.is_moving = true

## Handles unified target parameter - can be action string or coordinates
func _handle_target(target) -> void:
	# Check if target is a dictionary with coordinates
	if target is Dictionary and target.has("x") and target.has("y"):
		_navigating_to_coords = true
		_target_coords = Vector2(target["x"], target["y"])
		nav_agent.target_position = _target_coords
		body.is_moving = true
		body.update_debug_label("Patrol: Coords (%s)" % str(_target_coords))
		Messages.print_message("Moving to coordinates %s" % str(_target_coords), "Patrol")
	# Otherwise treat as action string
	elif target is String:
		_handle_action(target)
	else:
		push_warning("patrol_state: Unknown target type: %s" % str(target))

func move_cyclic(direction: int) -> void:
	_navigating_to_coords = false  # Waypoint navigation
	if sorted_waypoints.is_empty(): return

	current_waypoint_index = (current_waypoint_index + direction) % sorted_waypoints.size()
	if current_waypoint_index < 0:
		current_waypoint_index += sorted_waypoints.size()
	
	var target_node = sorted_waypoints[current_waypoint_index]
	body.update_debug_label("Patrol: %s" % target_node.name)
	
	nav_agent.target_position = target_node.global_position
	body.is_moving = true

# If we receive a command while ALREADY in this state
func enter_with_command(msg: Dictionary) -> void:
	if msg.has("target"):
		_handle_target(msg["target"])
	elif msg.has("action"):
		_handle_action(msg["action"])

func update_physics(_delta: float) -> void:
	if not body.is_moving and nav_agent.is_navigation_finished():
		return 
		
	if body.is_moving and nav_agent.is_navigation_finished():
		body.is_moving = false
		
		# Suppress if chasing (body handles Chase→Track internally)
		if body.is_chasing:
			body.update_debug_label("Arrived (chasing)")
			return
		
		# Notify mind based on navigation type
		if _navigating_to_coords:
			vesna.send_navigation_update("reached_target", "coords")
			body.update_debug_label("Arrived at coords")
		else:
			vesna.send_navigation_update("reached", "%d" % current_waypoint_index)
			body.update_debug_label("Arrived at waypoint")
		
		# Transition to Idle - mind decides next action
		Messages.print_message("Arrived. Awaiting orders...", "Patrol")
		state_machine.change_state_by_name("Idle")
