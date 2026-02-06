extends Control

# --- CONFIGURATION ---
const URL_GUARD_BOT: String = "http://localhost:5005/webhooks/rest/webhook"
const URL_DATE_BOT: String  = "http://localhost:5006/webhooks/rest/webhook"

# --- SIGNALS ---
signal interrogation_won(secret_info: String)
signal interrogation_failed

# --- NODES (MAIN UI) ---
@onready var agent_sprite: TextureRect = %AgentSprite
@onready var agent_name_label: Label = %AgentNameLabel
@onready var agent_text_label: RichTextLabel = %AgentText
@onready var user_input: LineEdit = %UserInput
@onready var http_request: HTTPRequest = %RasaRequest
@onready var continue_button: Button = %ContinueButton # The "Return to Maze" button

# --- NODES (LOG WINDOW) ---
@onready var log_window: PanelContainer = %LogWindow
@onready var log_text_label: RichTextLabel = %LogText
@onready var show_log_btn: Button = %LogButton
@onready var close_log_btn: Button = %CloseLogButton

# --- NODES (INTERROGATION HUD) ---
@onready var interrogation_hud: Control = %InterrogationHUD
@onready var ease_bar: ProgressBar = %EaseBar
@onready var suspicion_bar: ProgressBar = %SuspicionBar

# --- STATE ---
var current_guard_name: String = "unknown"
var current_mode: String = "GUARD" # "GUARD" or "DATE"
var current_api_url: String = URL_GUARD_BOT
var last_score: float = 0.0

# --- ASSETS ---
@export var guard_sprites: Dictionary = {
	"eugenia": preload("res://stages/chat/sprites/target_eugenia.png"),
	"susanna": preload("res://stages/chat/sprites/patrol2_susanna.png"),
	"rosanna": preload("res://stages/chat/sprites/patrol1_rosanna.png"),
	"polyanna": preload("res://stages/chat/sprites/patrol3_polyanna.png"),
	"marianna": preload("res://stages/chat/sprites/patrol4_marianna.png"),
	"unknown": preload("res://stages/chat/sprites/patrol1_rosanna.png")
}

func _ready() -> void:
	# 1. Connect Input & Networking
	%SendButton.pressed.connect(_on_send_pressed)
	user_input.text_submitted.connect(_on_send_pressed)
	http_request.request_completed.connect(_on_request_completed)
	
	# 2. Connect Log Window
	show_log_btn.pressed.connect(func(): log_window.show())
	close_log_btn.pressed.connect(func(): log_window.hide())
	
	# 3. Connect Scene Exit Button
	continue_button.pressed.connect(_on_continue_pressed)

	# 4. Initial UI State
	interrogation_hud.hide()
	log_window.hide()
	continue_button.hide()
	agent_text_label.text = "[i]Waiting...[/i]"

	# 5. Check GameManager for Target (Scene Switch Workflow)
	# (Requires GameManager autoload to be present)
	if get_node_or_null("/root/GameManager") and GameManager.target_guard_name != "":
		configure_bot(GameManager.target_guard_name)
	else:
		# Fallback for testing/debugging the scene directly
		agent_text_label.text = "[i]Debug Mode: Select a bot from debug menu[/i]"

# --- SETUP ENCOUNTER ---
func configure_bot(guard_name: String) -> void:
	current_guard_name = guard_name.to_lower()
	
	# 1. Update Sprite
	if guard_sprites.has(current_guard_name):
		agent_sprite.texture = guard_sprites[current_guard_name]
	else:
		agent_sprite.texture = guard_sprites["unknown"]
	
	agent_name_label.text = guard_name.capitalize()
	
	# 2. Reset UI
	user_input.editable = true
	%SendButton.disabled = false
	continue_button.hide()
	continue_button.text = "Return to Maze" # Reset default text

	# 3. Context Switch (Guard vs Date)
	if current_guard_name == "eugenia":
		current_mode = "DATE"
		current_api_url = URL_DATE_BOT # Port 5006
		_setup_date_mode()
		agent_text_label.text = "..."
	else:
		current_mode = "GUARD"
		current_api_url = URL_GUARD_BOT # Port 5005
		interrogation_hud.hide()
		agent_text_label.text = "[i]HALT! Who goes there?[/i]"

	# 4. Inform Rasa (Send invisible payload to set context)
	var hidden_payload: String = '/inform{"guard_name": "%s"}' % current_guard_name
	_send_to_rasa(hidden_payload)

func _setup_date_mode() -> void:
	interrogation_hud.show()
	var tween = create_tween().set_parallel(true)
	tween.tween_property(ease_bar, "value", 20.0, 0.5)
	tween.tween_property(suspicion_bar, "value", 0.0, 0.5)

# --- SENDING DATA ---
func _on_send_pressed(text_submitted: String = "") -> void:
	var text: String = user_input.text.strip_edges()
	if text.is_empty(): return
	
	_add_to_log("You", text)
	user_input.text = ""
	_send_to_rasa(text)

func _send_to_rasa(message_text: String) -> void:
	var data: Dictionary = {
		"sender": "godot_player",
		"message": message_text
	}
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var body: String = JSON.stringify(data)
	
	# Send to the correctly selected API URL (5005 or 5006)
	http_request.request(current_api_url, headers, HTTPClient.METHOD_POST, body)

# --- RECEIVING DATA ---
func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		agent_text_label.text = "[color=red]Error: Cannot reach brain.[/color]"
		return

	var json = JSON.new()
	var parse_error = json.parse(body.get_string_from_utf8())
	
	if parse_error != OK:
		printerr("JSON Parse Error: ", json.get_error_message())
		return
		
	var response_array = json.data
	
	if response_array is Array:
		for message in response_array:
			_process_single_message(message)

func _process_single_message(message: Dictionary) -> void:
	# 1. Text Update
	if "text" in message:
		agent_text_label.text = message["text"]
		_add_to_log(current_guard_name.capitalize(), message["text"])
		
		# LOGIC: If in Guard Mode, the turn ends immediately after the bot replies.
		if current_mode == "GUARD":
			_end_skirmish_turn()
	
	# 2. Custom Data Handling
	if "custom" in message:
		var data: Dictionary = message["custom"]
		
		# Capture Score
		if "ai_score_modifier" in data:
			last_score = data["ai_score_modifier"]
			_handle_guard_visuals(last_score)
			
		# Date Mode Scores
		if "ease_score" in data:
			_update_date_meters(data)
			
		# Game Events (Win/Loss)
		if "game_event" in data:
			_handle_game_event(data["game_event"], data)

# --- GUARD MODE LOGIC ---
func _end_skirmish_turn() -> void:
	# Lock input to prevent spamming
	user_input.editable = false
	%SendButton.disabled = true
	
	# Show "Return to Maze" button
	continue_button.show()
	continue_button.grab_focus()

func _handle_guard_visuals(score: float) -> void:
	# Optional: Add visual feedback for guard score (e.g. Flash Screen Green/Red)
	pass 

# --- DATE MODE LOGIC ---
func _update_date_meters(data: Dictionary) -> void:
	var ease_val: float = data.get("ease_score", 0.0)
	var sus_val: float = data.get("suspicion_score", 0.0)
	var delta_sus: float = data.get("delta_suspicion", 0.0)

	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(ease_bar, "value", ease_val, 0.6)
	tween.tween_property(suspicion_bar, "value", sus_val, 0.6)
	
	if delta_sus > 0:
		var flash = create_tween()
		agent_sprite.modulate = Color(1, 0.3, 0.3) 
		flash.tween_property(agent_sprite, "modulate", Color.WHITE, 0.3)

# --- DATE MODE EVENT HANDLING ---
func _handle_game_event(event_name: String, data: Dictionary) -> void:
	match event_name:
		"date_success":
			var secret: String = data.get("secret_info", "???")
			agent_text_label.text += "\n[color=green][b]TARGET CRACKED: %s[/b][/color]" % secret
			
			# Store win state
			GameManager.final_game_outcome = "win"
			GameManager.recovered_secret = secret
			
			# End the interaction
			_end_date_encounter()
			
		"date_failed":
			agent_text_label.text = "[shake level=10][color=red]SHE IS LEAVING![/color][/shake]"
			
			# Store loss state
			GameManager.final_game_outcome = "loss"
			
			# End the interaction
			_end_date_encounter()

func _end_date_encounter() -> void:
	# Lock input
	user_input.editable = false
	%SendButton.disabled = true
	
	# Show button with special text
	continue_button.text = "Finish Mission"
	continue_button.show()
	continue_button.grab_focus()

# --- EXIT LOGIC (BRANCHING) ---
func _on_continue_pressed() -> void:
	if current_mode == "DATE":
		# BRANCH A: Go to Ending Screen
		get_tree().change_scene_to_file("res://stages/ending/ending_screen.tscn")
		
	else:
		# BRANCH B: Return to Maze (Guard Logic)
		GameManager.last_encounter_score = last_score
		
		if last_score > 0:
			GameManager.last_encounter_result = "pacified"
			GameManager.pacified_guards.append(current_guard_name)
		else:
			GameManager.last_encounter_result = "alarm"

		get_tree().change_scene_to_file("res://stages/maze/test_maze.tscn")

# --- LOGIC UTILS ---
func _add_to_log(sender: String, text: String) -> void:
	var color: String = "white"
	if sender == "You": 
		color = "#88ccff" # Light Blue
	elif sender == "System": 
		color = "gray"
	else: 
		color = "#ffcc88" # Light Orange (Agent)
	
	log_text_label.append_text("[b][color=%s]%s:[/color][/b] %s\n" % [color, sender, text])
