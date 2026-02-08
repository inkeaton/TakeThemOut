extends Node2D

@onready var chat_interface: Control = $ChatInterface

func _ready() -> void:
	# Enable debug mode: no input locking, no scene changes, scores shown inline
	chat_interface.debug_mode = true
	
	# --- CONNECT GUARDS ---
	$BtnSusanna.pressed.connect(func(): _switch_to("susanna"))
	$BtnRosanna.pressed.connect(func(): _switch_to("rosanna"))
	$BtnPolyanna.pressed.connect(func(): _switch_to("polyanna"))
	$BtnMarianna.pressed.connect(func(): _switch_to("marianna"))

	# --- CONNECT TARGET (DATE) ---
	$BtnEugenia.pressed.connect(func(): _switch_to("eugenia"))

func _switch_to(guard_name: String) -> void:
	chat_interface.configure_bot(guard_name)
	chat_interface.user_input.grab_focus()
