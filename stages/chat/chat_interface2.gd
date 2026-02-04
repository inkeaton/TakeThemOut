extends Control

const RASA_URL = "http://localhost:5005/webhooks/rest/webhook"

# --- UI NODES (Make sure to set these as Unique Names in Scene %Name) ---
@onready var agent_sprite = %AgentSprite
@onready var agent_name_label = %AgentNameLabel
@onready var agent_text_label = %AgentText
@onready var user_input = %UserInput
@onready var send_button = %SendButton
@onready var http_request = %RasaRequest

# --- LOG WINDOW NODES ---
@onready var log_window = %LogWindow
@onready var log_text = %LogText
@onready var close_log_btn = %CloseLogButton
@onready var show_log_btn = %LogButton

# --- SPRITES (Preload your assets here) ---
# Replace with actual paths to your png files
var sprites = {
	"susanna": preload("res://stages/chat/sprites/patrol2_susanna.png"),
	"rosanna": preload("res://stages/chat/sprites/patrol1_rosanna.png"),
	"polyanna": preload("res://stages/chat/sprites/patrol3_polyanna.png"),
	"marianna": preload("res://stages/chat/sprites/patrol4_marianna.png"),
	"unknown": preload("res://stages/chat/sprites/patrol1_rosanna.png")
}

var current_guard_name = "unknown"

func _ready():
	# Connect Signals
	send_button.pressed.connect(_on_send_pressed)
	user_input.text_submitted.connect(_on_send_pressed)
	http_request.request_completed.connect(_on_request_completed)
	
	# Log Logic
	show_log_btn.pressed.connect(func(): log_window.show())
	close_log_btn.pressed.connect(func(): log_window.hide())

	# Initialize Interface
	log_window.hide()
	agent_text_label.text = "[i]Waiting for interaction...[/i]"

# --- SETUP FUNCTION ---
func configure_bot(guard_name: String):
	current_guard_name = guard_name
	
	# 1. Update Visuals
	var key = guard_name.to_lower()
	if sprites.has(key):
		agent_sprite.texture = sprites[key]
	else:
		agent_sprite.texture = sprites["unknown"]
	
	agent_name_label.text = guard_name.capitalize()
	
	# 2. Reset Text
	agent_text_label.text = "..."
	_add_to_log("System", "Encounter started with " + guard_name.capitalize())
	
	# 3. Inform Rasa (Context Switch)
	var hidden_payload = "/inform{\"guard_name\": \"%s\"}" % guard_name
	_send_to_rasa(hidden_payload, true) # Hidden = true

func _on_send_pressed(text_submitted = ""):
	var user_text = user_input.text.strip_edges()
	if user_text.is_empty():
		return

	# Clear input
	user_input.text = ""
	
	# Add to history log (but NOT the main dialogue box)
	_add_to_log("You", user_text)
	
	# Send to Rasa
	_send_to_rasa(user_text)

func _send_to_rasa(text_to_send: String, is_hidden: bool = false):
	var data = { "sender": "godot_player", "message": text_to_send }
	var headers = ["Content-Type: application/json"]
	http_request.request(RASA_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(data))

func _on_request_completed(result, response_code, headers, body):
	if response_code != 200:
		agent_text_label.text = "[color=red]Connection Error[/color]"
		return

	var json = JSON.new()
	json.parse(body.get_string_from_utf8())
	var response_array = json.get_data()
	
	if response_array is Array:
		for message in response_array:
			# 1. Update the Main Dialogue Box (Visual Novel Style)
			if "text" in message:
				agent_text_label.text = message["text"] # Replaces old text!
				_add_to_log(current_guard_name.capitalize(), message["text"])
			
			# 2. Handle Custom Score Data
			if "custom" in message and "ai_score_modifier" in message["custom"]:
				var score = message["custom"]["ai_score_modifier"]
				_handle_score_visuals(score)

func _add_to_log(sender: String, text: String):
	# Appends to the hidden history window
	var color = "white"
	if sender == "You": color = "#88ccff" # Light Blue
	elif sender == "System": color = "gray"
	else: color = "#ffcc88" # Light Orange (Agent)
	
	log_text.append_text("[b][color=%s]%s:[/color][/b] %s\n" % [color, sender, text])

func _handle_score_visuals(score: float):
	# Optional: Flash the screen or play a sound based on score
	if score > 0:
		agent_name_label.modulate = Color.GREEN
	elif score < 0:
		agent_name_label.modulate = Color.RED
	else:
		agent_name_label.modulate = Color.WHITE
		
	# Reset color after 1 second (Requires a Timer node or Tween)
	var tween = create_tween()
	tween.tween_property(agent_name_label, "modulate", Color.WHITE, 1.0).set_delay(0.5)
