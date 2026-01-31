# TrackState.gd
extends State

@export_group("Settings")
@export var default_max_crumbs: int = 5

# Internal State
var last_crumb_timestamp: int = 0
var crumbs_tracked_count: int = 0 
var current_max_crumbs: int = 5

# FIX: Remove @onready. We will assign this in enter() when 'body' is guaranteed to exist.
var scent_cast: ShapeCast2D 

func enter(_msg: Dictionary = {}) -> void:
	# FIX: Lazy Initialization
	# We grab the node the first time we enter this state.
	if not scent_cast:
		scent_cast = body.get_node("%ScentCast")

	body.update_debug_label("Lost Visual. Sniffing...")
	
	# Reset Memory
	last_crumb_timestamp = 0 
	crumbs_tracked_count = 0
	
	# Apply patience settings if passed, otherwise default
	current_max_crumbs = _msg.get("patience", default_max_crumbs)

func update_physics(_delta: float) -> void:
	# 1. Wait until we arrive at the current destination before sniffing
	if not nav_agent.is_navigation_finished():
		return

	# 2. Perform the active scan
	scent_cast.force_shapecast_update()

	# FAILURE CASE 1: Trail Cold (No scents at all)
	if not scent_cast.is_colliding():
		body.update_debug_label("Trail Cold.")
		Messages.print_message("Trail cold. Reporting to Mind...", "Patrol")
		_fail_to_idle("cold_trail")
		# disable now
		scent_cast.enabled = false
		return
	
	# disable now
	scent_cast.enabled = false

	# 3. Process Results
	var best_crumb: Crumb = null
	var best_timestamp: int = -1

	for i in scent_cast.get_collision_count():
		var collider = scent_cast.get_collider(i)
		if not collider is Crumb: continue
		
		# Logic: Must be newer than history, and the newest available
		if collider.timestamp > last_crumb_timestamp:
			if collider.timestamp > best_timestamp:
				best_timestamp = collider.timestamp
				best_crumb = collider
	
	# 4. Act
	if best_crumb:
		crumbs_tracked_count += 1
		
		# FAILURE CASE 2: Patience Limit
		if crumbs_tracked_count > current_max_crumbs:
			body.update_debug_label("Patience Lost.")
			Messages.print_message("Patience limit (%d). Reporting...", "Patrol")
			_fail_to_idle("patience_limit")
			return

		# Move to crumb
		nav_agent.target_position = best_crumb.global_position
		last_crumb_timestamp = best_timestamp
		body.is_moving = true 
		
		body.update_debug_label("Tracking: Crumb %d/%d" % [crumbs_tracked_count, current_max_crumbs])
		Messages.print_message("Tracking crumb %d..." % crumbs_tracked_count, "Patrol")
		
	else:
		# FAILURE CASE 3: End of Line
		body.update_debug_label("End of Trail.")
		Messages.print_message("End of trail. Reporting...", "Patrol")
		_fail_to_idle("end_of_trail")

func _fail_to_idle(reason: String) -> void:
	# Transition to IDLE state and send report
	vesna.send_target_lost(body.global_position, reason)
	state_machine.change_state_by_name("Idle")
