extends Node2D

# --- NODES ---
@onready var player: CharacterBody2D = %Player

# UI Nodes (Make sure you added these to a CanvasLayer in your scene!)
@onready var loading_overlay: Sprite2D = %LoadingOverlay
@onready var loading_label: Label = %LoadingLabel

func _ready() -> void:
	# -------------------------------------------------------------------------
	# 1. GAMEPLAY: Handle Return from Chat
	# -------------------------------------------------------------------------
	if GameManager.last_encounter_result != "":
		_handle_return_from_chat()
	
	# Clear data so we don't re-trigger it on a simple reload
	GameManager.reset_encounter_data()

	# -------------------------------------------------------------------------
	# 2. INFRASTRUCTURE: Start the Mind (Jason/Gradle)
	# -------------------------------------------------------------------------
	# We must start the server every time we enter the maze to ensure clean connection.
	ServerManager.start_jason_server()
	
	# If Java is already connected (rare, but possible), just go.
	# Otherwise, pause and wait for the handshake.
	if ServerManager.is_jason_ready:
		_on_mind_ready()
	else:
		_enter_loading_state()

# --- JASON LOADING LOGIC ---

func _enter_loading_state() -> void:
	print("Waiting for Jason Mind to boot...")
	
	# Pause the game so guards don't move before they have brains
	get_tree().paused = true 
	
	# Show UI
	if loading_overlay: loading_overlay.show()
	if loading_label: 
		loading_label.text = "INITIALIZING AGENTS..."
		loading_label.show()
	
	# Connect to the signal emitted by ServerManager when Port 9200 receives connection
	if not ServerManager.jason_service_ready.is_connected(_on_mind_ready):
		ServerManager.jason_service_ready.connect(_on_mind_ready)

func _on_mind_ready() -> void:
	print("Mind Connected. Starting Game.")
	
	# Hide UI
	if loading_overlay: loading_overlay.hide()
	if loading_label: loading_label.hide()
	
	# Unpause
	get_tree().paused = false
	
	# Cleanup connection
	if ServerManager.jason_service_ready.is_connected(_on_mind_ready):
		ServerManager.jason_service_ready.disconnect(_on_mind_ready)

# --- ENCOUNTER LOGIC ---

func trigger_encounter(guard_name: String) -> void:
	print("⚔️ Encounter triggered with: ", guard_name)
	
	# 1. Setup Data for the Chat Scene
	GameManager.target_guard_name = guard_name
	
	# 2. Switch Scene (deferred to avoid removing collision nodes during physics callback)
	# This effectively destroys the current Maze scene, triggering _exit_tree()
	get_tree().call_deferred("change_scene_to_file", "res://stages/chat/chat_interface.tscn")

func _handle_return_from_chat() -> void:
	print("Returned from chat. Result: ", GameManager.last_encounter_result)
	
	if GameManager.last_encounter_result == "pacified":
		print("   -> Guard was pacified.")
		# Gameplay Idea: You could delete the specific guard here if you tracked their name/path
		# For now, we just proceed.
		
	elif GameManager.last_encounter_result == "alarm":
		print("   -> ALARM TRIGGERED!")
		# Gameplay Idea: Increase difficulty or spawn reinforcements

# --- CLEANUP ---

func _exit_tree() -> void:
	# CRITICAL: Stop the Jason server when we leave the maze.
	# This ensures that when we return (or go to Date), the port is freed
	# and we can perform a fresh handshake.
	ServerManager.stop_jason_server()
