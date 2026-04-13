## ChaseState: Executes active pursuit behavior while target remains visible.
extends State

# --- Configuration ---
@export var chase_path_refresh_interval: float = 0.1

# --- State ---
var _chase_cooldown: float = 0.0
var stored_patience: int = 5  # Default patience for tracking

# --- Lifecycle ---

func enter(msg: Dictionary = {}) -> void:
	body.update_debug_label("CHASING PLAYER!")
	
	# Mark as chasing (blocks patrol/move_to commands)
	body.is_chasing = true
	
	# Start moving immediately
	if body.target_player:
		nav_agent.target_position = body.target_player.global_position
		
	# Store patience if provided by the mind
	if msg.has("patience"):
		stored_patience = int(msg.get("patience", 5))

func update_physics(delta: float) -> void:
	# If we've lost the player, transition to Track (backup for missed signal)
	if not body.target_player:
		Messages.print_message("Lost visual on target. Switching to Track.", "Patrol")
		var patience_msg = {"patience": stored_patience}
		state_machine.change_state_by_name("Track", patience_msg)
		return
	
	# Scan for idle patrol allies who could help coordinate
	body.scan_for_chase_allies()
		
	_chase_cooldown -= delta
	if _chase_cooldown <= 0:
		nav_agent.target_position = body.target_player.global_position
		_chase_cooldown = chase_path_refresh_interval
