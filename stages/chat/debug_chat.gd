extends Node2D

@onready var chat_interface: Control = $ChatInterface

func _ready() -> void:
	# --- CONNECT GUARDS ---
	# These will trigger the standard "Excuses" logic
	$BtnSusanna.pressed.connect(func(): chat_interface.configure_bot("susanna"))
	$BtnRosanna.pressed.connect(func(): chat_interface.configure_bot("rosanna"))
	$BtnPolyanna.pressed.connect(func(): chat_interface.configure_bot("polyanna"))
	$BtnMarianna.pressed.connect(func(): chat_interface.configure_bot("marianna"))

	# --- CONNECT TARGET (DATE) ---
	# This triggers the "Interrogation/Date" logic and shows the HUD bars
	$BtnEugenia.pressed.connect(func(): chat_interface.configure_bot("eugenia"))
