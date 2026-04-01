## PatrolIdleState: Holds patrol body in place while awaiting mind-driven transitions.
## Role: state
## Responsibilities:
## - Stop movement and clear chase lock when entered.
## - Keep vision logic available while not autonomously transitioning.
## Dependencies:
## - Receives transition commands from mind via body command handlers.
extends State

# --- Behavior ---
## Idle state: Patrol waits for mind instructions.
## Vision remains enabled - can still detect player.
## All state exits are controlled by mind via transition_to.

func enter(_msg: Dictionary = {}) -> void:
	body.update_debug_label("IDLE (Awaiting Orders)")
	
	# Stop moving
	nav_agent.target_position = body.global_position
	body.velocity = Vector2.ZERO
	body.is_moving = false
	
	# Release chase lock when entering idle
	body.is_chasing = false
	
	Messages.print_message("Awaiting orders...", "Patrol")

func update_physics(_delta: float) -> void:
	# No autonomous behavior - wait for mind's transition_to command
	pass
