## CaptainBody: Specializes patrol body behavior with captain-specific sighting reaction.
## - Inherits from `bodies/guards/patrols/patrol.gd`.
extends "res://bodies/guards/patrols/patrol.gd"

# --- Override: Detection Reaction ---
# Captain behavior: detect player, broadcast alert tone, then chase.
func react_to_player() -> void:
	# Keep patrol chase transition semantics.
	if state_machine.current_state.name != "Chase":
		state_machine.change_state_by_name("Chase")
		
	Messages.print_message("CAPTAIN SIGHTING! Alerting Squad!", "Captain")
	
	# Send standard sighting payload to the mind bridge.
	vesna.send_sight_with_position("player", 
	target_player.get_instance_id(), target_player.global_position)
