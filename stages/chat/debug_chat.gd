## DebugChatController: Provides quick guard/date switching for local chat debugging.
extends Node2D

# --- Nodes ---
@onready var chat_interface: Control = $ChatInterface

# --- Lifecycle ---
func _ready() -> void:
	# Enable debug mode: no input locking, no scene changes, scores shown inline
	chat_interface.debug_mode = true
	
	# --- Connect Guards ---
	$BtnSusanna.pressed.connect(func(): _switch_to("susanna"))
	$BtnRosanna.pressed.connect(func(): _switch_to("rosanna"))
	$BtnPolyanna.pressed.connect(func(): _switch_to("polyanna"))
	$BtnMarianna.pressed.connect(func(): _switch_to("marianna"))

	# --- Connect Target (Date) ---
	$BtnEugenia.pressed.connect(func(): _switch_to("eugenia"))

# --- Helpers ---

func _switch_to(guard_name: String) -> void:
	chat_interface.configure_bot(guard_name)
	chat_interface.user_input.grab_focus()
