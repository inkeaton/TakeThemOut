## TargetTrigger: Starts the date/chat branch when the player reaches Eugenia's trigger area.
extends Area2D

# --- Behavior ---
## When the player enters this area, the dating sequence begins.

# --- Lifecycle ---
func _ready() -> void:
	# Detect the player (collision_layer = 4, i.e. layer 3)
	collision_layer = 0
	collision_mask = 4
	monitoring = true
	monitorable = false

	body_entered.connect(_on_body_entered)


# --- Trigger Handling ---
func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		print("Target reached! Starting dating sequence...")
		# Deferred to avoid removing collision nodes during physics callback
		call_deferred("_start_date")

# --- Scene Transition ---
func _start_date() -> void:
	GameManager.target_guard_name = "eugenia"
	get_tree().change_scene_to_file("res://stages/chat/chat_interface.tscn")
