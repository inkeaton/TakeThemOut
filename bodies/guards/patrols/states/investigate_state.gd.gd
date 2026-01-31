# InvestigateState.gd
extends State

@export var investigation_radius: float = 400.0
@export var default_points: int = 3

var points_to_visit: Array[Vector2] = []
var current_index: int = 0

func enter(msg: Dictionary = {}) -> void:
	var count = msg.get("points", default_points)
	generate_points(int(count))
	
	current_index = 0
	body.update_debug_label("Starting Investigation (%d pts)..." % count)
	
	# Kickstart movement if we have points
	if not points_to_visit.is_empty():
		_move_to_next()

func generate_points(count: int) -> void:
	points_to_visit.clear()
	var map_rid = nav_agent.get_navigation_map()
	
	for i in range(count):
		# Random point in circle
		var random_offset = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(100.0, investigation_radius)
		var target_pos = body.global_position + random_offset
		
		# Snap to NavMesh
		var valid_pos = NavigationServer2D.map_get_closest_point(map_rid, target_pos)
		points_to_visit.append(valid_pos)
	
	Messages.print_message("Generated %d investigation points." % points_to_visit.size(), "Patrol")

func update_physics(_delta: float) -> void:
	# Wait for arrival
	if not nav_agent.is_navigation_finished():
		return
	
	# Move to next or finish
	if current_index < points_to_visit.size():
		_move_to_next()
	else:
		_finish_investigation()

func _move_to_next() -> void:
	var pt = points_to_visit[current_index]
	nav_agent.target_position = pt
	body.is_moving = true
	
	body.update_debug_label("Investigating: %d/%d" % [current_index + 1, points_to_visit.size()])
	Messages.print_message("Investigating point %d..." % (current_index + 1), "Patrol")
	
	current_index += 1

func _finish_investigation() -> void:
	body.update_debug_label("Investigation Done.")
	Messages.print_message("Investigation complete.", "Patrol")
	
	# Notify mind
	vesna.send_event("investigation", {
		"status": "complete",
		"reason": "points_finished"
	})
	
	state_machine.change_state_by_name("Idle")
