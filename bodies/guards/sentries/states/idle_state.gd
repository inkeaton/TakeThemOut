## SentryIdleState: Keeps sentry passive while waiting for explicit mind instructions.
extends State

# --- Behavior ---
## Idle state: Vision disabled, waiting for mind instructions only.
## No autonomous transitions - mind controls all exits from this state.

func enter(_msg: Dictionary = {}) -> void:
	# Disable vision - sentry is waiting for orders
	body.update_debug_label("Idle")
	body.vision_cone.visible = false
	body.vision_cone.monitoring = false
	Messages.print_message("Awaiting orders...", "Sentry")

func update_physics(_delta: float) -> void:
	# No autonomous behavior - wait for mind's transition_to command
	pass
