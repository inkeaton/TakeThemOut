## GameManager: Stores cross-scene run state for encounters, sympathy deltas, and ending outcomes.
## Role: autoload
## Responsibilities:
## - Persist encounter context between maze, chat, and ending scenes.
## - Aggregate sympathy updates to be relayed to Jason setup messages.
## - Provide name mapping between chat display names and Jason agent names.
## Dependencies:
## - Consumed by `stages/maze/test2.gd` and `stages/chat/chat_interface.gd`.
extends Node

# --- Maze To Chat Data ---
var target_guard_name: String = ""

# --- Chat To Maze Data (Guards) ---
var last_encounter_score: float = 0.0
var pacified_guards: Array[String] = []

# --- Sympathy Updates (Across Encounters) ---
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

# --- Chat To Ending Data (Date) ---
var final_game_outcome: String = "" # "win" or "loss"
var recovered_secret: String = ""   # The info you stole (e.g., "Luca")

func reset_encounter_data() -> void:
	target_guard_name = ""
	last_encounter_score = 0.0
