extends Node

# --- DATA PASSED FROM MAZE TO CHAT ---
var target_guard_name: String = ""

# --- DATA PASSED FROM CHAT TO MAZE (Guards) ---
var last_encounter_score: float = 0.0
var last_encounter_result: String = "" 
var pacified_guards: Array[String] = []

# --- SYMPATHY UPDATES (Accumulated across encounters, sent to Jason on maze reload) ---
# Maps Jason agent name → cumulative sympathy delta  (e.g. {"patrol_rosanna": 0.4})
var sympathy_updates: Dictionary = {}

# Display name → Jason agent name mapping (only patrols & captains can be encountered)
const GUARD_NAME_MAP: Dictionary = {
	"rosanna": "patrol_rosanna",
	"susanna": "patrol_susanna",
	"polyanna": "patrol_polyanna",
	"marianna": "patrol_marianna",
	"daniele": "captain_daniele",
	"samuele": "captain_samuele",
}

# Convert sympathy_updates dict → JSON-ready array for the Jason setup message
func get_sympathy_payload() -> Array:
	var result: Array = []
	for agent_name in sympathy_updates:
		var delta: float = sympathy_updates[agent_name]
		if delta != 0.0:
			result.append({"agent": agent_name, "value": delta})
	return result

# --- DATA PASSED FROM CHAT TO ENDING (Date) ---
var final_game_outcome: String = "" # "win" or "loss"
var recovered_secret: String = ""   # The info you stole (e.g., "Luca")

func reset_encounter_data() -> void:
	target_guard_name = ""
	last_encounter_score = 0.0
	last_encounter_result = ""
