extends "res://bodies/guards/patrols/patrol.gd"

# We override the react_to_player function.
# The Captain acts like a Sentry: he sees you, he shouts, THEN he chases.
func react_to_player() -> void:
	# 1. Global Transition Rule (Same as Patrol)
	if state_machine.current_state.name != "Chase":
		state_machine.change_state_by_name("Chase")
		
	Messages.print_message("CAPTAIN SIGHTING! Alerting Squad!", "Captain")
	
	# 2. Standard Sight Report
	vesna.send_sight_with_position("player", 
	target_player.get_instance_id(), target_player.global_position)
	
	# 3. EXTRA: Trigger the 'Alert' signal (Just like Sentry)
	# This tells the Mind to broadcast "player_spotted_at" to everyone else.
	vesna.send_signal("alert", "triggered", "Captain spotted player")
