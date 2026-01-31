extends State

var destination: Vector2 = Vector2.ZERO

func enter(msg: Dictionary = {}) -> void:
	if msg.has("pos_x") and msg.has("pos_y"):
		destination = Vector2(msg["pos_x"], msg["pos_y"])
		
		# Set navigation target
		nav_agent.target_position = destination
		body.is_moving = true
		
		body.update_debug_label("Travel: " + str(destination))
		Messages.print_message("Received alert. Moving to " + str(destination), "Patrol")
	else:
		Messages.print_message("Travel State entered without coordinates. Returning to Idle.", "Patrol")
		state_machine.change_state_by_name("Idle")

func update_physics(_delta: float) -> void:
	# 1. Wait for arrival
	if not nav_agent.is_navigation_finished():
		return
		
	# 2. Arrival Logic
	body.update_debug_label("Arrived (Waiting for orders)")
	Messages.print_message("Arrived at destination. Notifying Mind.", "Patrol")
	
	# Stop moving
	body.is_moving = false
	
	# Notify Mind using the existing navigation protocol
	# We use a special status "reached_target" and a generic name "coords"
	vesna.send_navigation_update("reached_target", "coords")
	
	# Enter Idle to wait for the next command (Investigate, Patrol, etc.)
	state_machine.change_state_by_name("Idle")
