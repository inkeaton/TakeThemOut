extends Node

# --- DATA PASSED FROM MAZE TO CHAT ---
var target_guard_name: String = ""

# --- DATA PASSED FROM CHAT TO MAZE (Guards) ---
var last_encounter_score: float = 0.0
var last_encounter_result: String = "" 
var pacified_guards: Array[String] = []

# --- DATA PASSED FROM CHAT TO ENDING (Date) ---
var final_game_outcome: String = "" # "win" or "loss"
var recovered_secret: String = ""   # The info you stole (e.g., "Luca")

func reset_encounter_data() -> void:
	target_guard_name = ""
	last_encounter_score = 0.0
	last_encounter_result = ""
