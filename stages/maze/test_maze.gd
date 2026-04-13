## TestMazeController: Orchestrates maze runtime flow, mind startup, and chat return handling.
extends Node2D

# --- Nodes ---
@onready var player: CharacterBody2D = %Player

# UI Nodes (Make sure you added these to a CanvasLayer in your scene!)
@onready var loading_overlay: Sprite2D = %LoadingOverlay
@onready var loading_label: Label = %LoadingLabel

func _ready() -> void:
	# 1. Clear encounter data when entering maze.
	GameManager.reset_encounter_data()

	# 2. Infrastructure: start the mind (Jason/Gradle).
	# We must start the server every time we enter the maze to ensure clean connection.
	ServerManager.start_jason_server()
	
	# If Java is already connected (rare), proceed immediately.
	# Otherwise, pause and wait for the handshake.
	if ServerManager.is_jason_ready:
		_on_mind_ready()
	else:
		_enter_loading_state()

# --- Jason Loading Logic ---

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
	
	# Send any queued sympathy updates to the director (ready_agent)
	_send_sympathy_updates()
	
	# Hide UI
	if loading_overlay: loading_overlay.hide()
	if loading_label: loading_label.hide()
	
	# Unpause
	get_tree().paused = false
	
	# Cleanup connection
	if ServerManager.jason_service_ready.is_connected(_on_mind_ready):
		ServerManager.jason_service_ready.disconnect(_on_mind_ready)

# --- Sympathy Relay ---

func _send_sympathy_updates() -> void:
	var payload: Array = GameManager.get_sympathy_payload()
	if payload.is_empty():
		print("No sympathy updates to send.")
		return
	
	# Build the setup message matching VesnaAgent.handleSetup() format
	var setup_msg: Dictionary = {
		"sender": "body",
		"receiver": "director",
		"type": "setup",
		"data": {
			"sympathies": payload
		}
	}
	ServerManager.send_to_director(setup_msg)
	print("Sent sympathy updates to director: ", payload)

# --- Encounter Logic ---

func trigger_encounter(guard_name: String) -> void:
	print("Encounter triggered with: ", guard_name)
	
	# 1. Setup Data for the Chat Scene
	GameManager.target_guard_name = guard_name
	
	# 2. Switch Scene (deferred to avoid removing collision nodes during physics callback)
	# This effectively destroys the current Maze scene, triggering _exit_tree()
	get_tree().call_deferred("change_scene_to_file", "res://stages/chat/chat_interface.tscn")

# --- Cleanup ---

func _exit_tree() -> void:
	# CRITICAL: Stop the Jason server when we leave the maze.
	# This ensures that when we return (or go to Date), the port is freed
	# and we can perform a fresh handshake.
	ServerManager.stop_jason_server()
