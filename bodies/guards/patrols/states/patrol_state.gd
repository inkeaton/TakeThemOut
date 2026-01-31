extends State

var current_waypoint_index: int = -1 
var sorted_waypoints: Array[Node2D] = []

func enter(msg: Dictionary = {}) -> void:
	# If this is the first run, cache waypoints
	if sorted_waypoints.is_empty():
		_cache_waypoints()
	
	# Handle immediate commands (e.g., "Resume", "Next")
	if msg.has("action"):
		_handle_action(msg["action"])
	else:
		body.update_debug_label("Patrolling")

func _cache_waypoints() -> void:
	var raw_nodes = get_tree().get_nodes_in_group("waypoints")
	for node in raw_nodes:
		if node is Node2D:
			sorted_waypoints.append(node)
	sorted_waypoints.sort_custom(func(a, b): return a.name < b.name)

func _handle_action(action: String) -> void:
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
			Messages.print_message("Moving to random waypoint %s" % target_node.name, "Captain")
			
			nav_agent.target_position = target_node.global_position
			body.is_moving = true

func move_cyclic(direction: int) -> void:
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
	if msg.has("action"):
		_handle_action(msg["action"])

func update_physics(_delta: float) -> void:
	if not body.is_moving and nav_agent.is_navigation_finished():
		return 
		
	if body.is_moving and nav_agent.is_navigation_finished():
		body.is_moving = false
		vesna.send_navigation_update("reached", "%d" % current_waypoint_index)
		body.update_debug_label("Waiting at Waypoint...")
