## IntroController: Handles intro menu interactions and transitions into game startup flow.
extends Control

# --- Configuration ---
const LOADING_SCREEN_PATH: String = "res://stages/loading_screen/LoadingScreen.tscn"

# --- Nodes ---
@onready var start_button: Button = %StartButton
@onready var quit_button: Button = %QuitButton

# --- Lifecycle ---
func _ready() -> void:
	# Connect buttons
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	# Ensure the mouse is visible if you came from a hidden-mouse gameplay section
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# --- Actions ---

func _on_start_pressed() -> void:
	print("Starting Game Sequence...")
	# Transition to the Loading Screen, which will start the Servers
	get_tree().change_scene_to_file(LOADING_SCREEN_PATH)

func _on_quit_pressed() -> void:
	print("Quitting...")
	ServerManager.stop_all_servers()
	get_tree().quit()
