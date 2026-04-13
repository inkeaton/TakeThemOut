## ChatInterface: Runs interrogation/date chat flow and bridges UI with Rasa responses.
extends Control

# --- Configuration ---
const URL_GUARD_BOT: String = "http://localhost:5005/webhooks/rest/webhook"
const URL_DATE_BOT: String  = "http://localhost:5006/webhooks/rest/webhook"
const CHAT_SENDER_ID: String = "godot_player"

# --- Signals ---
@warning_ignore("unused_signal")
signal interrogation_won(secret_info: String)
@warning_ignore("unused_signal")
signal interrogation_failed

# --- Nodes (Main UI) ---
@onready var agent_sprite: TextureRect = %AgentSprite
@onready var agent_name_label: Label = %AgentNameLabel
@onready var agent_text_label: RichTextLabel = %AgentText
@onready var user_input: LineEdit = %UserInput
@onready var http_request: HTTPRequest = %RasaRequest
@onready var continue_button: Button = %ContinueButton # The "Return to Maze" button

# --- Nodes (Log Window) ---
@onready var log_window: PanelContainer = %LogWindow
@onready var log_text_label: RichTextLabel = %LogText
@onready var show_log_btn: Button = %LogButton
@onready var close_log_btn: Button = %CloseLogButton

# --- Nodes (Interrogation HUD) ---
@onready var interrogation_hud: Control = %InterrogationHUD
@onready var ease_bar: ProgressBar = %EaseBar
@onready var suspicion_bar: ProgressBar = %SuspicionBar

# --- State ---
var current_guard_name: String = "unknown"
var current_mode: String = "GUARD" # "GUARD" or "DATE"
var current_api_url: String = URL_GUARD_BOT
var last_score: float = 0.0
var debug_mode: bool = false  # When true: no input locking, no scene changes, score shown inline
var _debug_cumulative_score: float = 0.0  # Running total for debug display

# --- Assets ---
@export var guard_sprites: Dictionary = {
	"eugenia": preload("res://stages/chat/sprites/target_eugenia.png"),
	"susanna": preload("res://stages/chat/sprites/patrol2_susanna.png"),
	"rosanna": preload("res://stages/chat/sprites/patrol1_rosanna.png"),
	"polyanna": preload("res://stages/chat/sprites/patrol3_polyanna.png"),
	"marianna": preload("res://stages/chat/sprites/patrol4_marianna.png"),
	"daniele": preload("res://bodies/guards/captains/res/capitan1_daniele.png"),
	"samuele": preload("res://bodies/guards/captains/res/capitan2_samuele.png"),
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

# --- Setup Encounter ---
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
	user_input.visible = true  # Restore if previously hidden (captain mode)
	%SendButton.disabled = false
	%SendButton.visible = true
	continue_button.hide()
	continue_button.text = "Return to Maze" # Reset default text
	last_score = 0.0
	
	# In debug mode: clear the log and reset cumulative score on guard switch
	if debug_mode:
		log_text_label.clear()
		_debug_cumulative_score = 0.0

	# 3. Context Switch (Captain vs Guard vs Date)
	if current_guard_name in ["daniele", "samuele"]:
		current_mode = "CAPTAIN"
		interrogation_hud.hide()
		# Hide input — captains don't talk
		user_input.editable = false
		user_input.visible = false
		%SendButton.disabled = true
		%SendButton.visible = false
		# Per-captain dismissal line
		if current_guard_name == "daniele":
			agent_text_label.text = "[i]I have nothing to tell you. Get lost.[/i]"
		else:
			agent_text_label.text = "[i]You're wasting my time. Scram.[/i]"
		# Show return button immediately
		continue_button.show()
		continue_button.grab_focus()
		return  # Skip Rasa payload — no bot interaction
		
	elif current_guard_name == "eugenia":
		current_mode = "DATE"
		current_api_url = URL_DATE_BOT # Port 5006
		_setup_date_mode()
		agent_text_label.text = "..."
	else:
		current_mode = "GUARD"
		current_api_url = URL_GUARD_BOT # Port 5005
		interrogation_hud.hide()
		agent_text_label.text = "[i]HALT! Who goes there?[/i]"

	# 4. Inform Rasa of guard name (Send invisible payload to set context)
	if current_mode == "GUARD":
		var hidden_payload: String = '/inform{"guard_name": "%s"}' % current_guard_name
		_send_to_rasa(hidden_payload)

func _setup_date_mode() -> void:
	interrogation_hud.show()
	var tween = create_tween().set_parallel(true)
	tween.tween_property(ease_bar, "value", 20.0, 0.5)
	tween.tween_property(suspicion_bar, "value", 0.0, 0.5)

# --- Sending Data ---
func _on_send_pressed(_text_submitted: String = "") -> void:
	if current_mode == "CAPTAIN": return  # Captains don't chat
	var text: String = user_input.text.strip_edges()
	if text.is_empty(): return
	
	_add_to_log("You", text)
	user_input.text = ""
	_send_to_rasa(text)

func _send_to_rasa(message_text: String) -> void:
	var data: Dictionary = {
		"sender": CHAT_SENDER_ID,
		"message": message_text
	}
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var body: String = JSON.stringify(data)
	
	# Send to the correctly selected API URL (5005 or 5006)
	http_request.request(current_api_url, headers, HTTPClient.METHOD_POST, body)

# --- Receiving Data ---
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
	if message.is_empty():
		return

	if current_mode == "GUARD" and not _validate_guard_payload(message):
		return

	if current_mode == "DATE" and not _validate_date_payload(message):
		return

	# 1. Text Update
	if "text" in message:
		agent_text_label.text = message["text"]
		_add_to_log(current_guard_name.capitalize(), message["text"])
		
		# LOGIC: If in Guard Mode, the turn ends immediately after the bot replies.
		if current_mode == "GUARD" and not debug_mode:
			_end_skirmish_turn()
	
	# 2. Custom Data Handling
	if "custom" in message:
		var data: Dictionary = message["custom"]
		
		# Capture Score
		if "sympathy_score" in data:
			last_score = data["sympathy_score"]
			_handle_guard_visuals(last_score)
			
			# In debug mode: show score and intent inline in the log
			if debug_mode:
				_debug_cumulative_score += last_score
				var intent: String = data.get("detected_intent", "?")
				var score_color: String = "#66ff66" if last_score > 0 else "#ff6666"
				_add_to_log("System", "[color=%s]Score: %+.2f[/color]  |  Intent: %s  |  Total: %+.2f" % [score_color, last_score, intent, _debug_cumulative_score])
			
		# Date Mode Scores
		if "ease_score" in data:
			_update_date_meters(data)
			
		# Game Events (Win/Loss)
		if "game_event" in data and data["game_event"] is String:
			_handle_game_event(data["game_event"], data)

func _validate_guard_payload(message: Dictionary) -> bool:
	if not ("text" in message or "custom" in message):
		return true

	if not ("custom" in message):
		return true

	if not (message["custom"] is Dictionary):
		_fail_fast("Guard response missing valid 'custom' payload.")
		return false

	var data: Dictionary = message["custom"]
	if not ("sympathy_score" in data) or not (data["sympathy_score"] is float or data["sympathy_score"] is int):
		_fail_fast("Guard payload missing numeric 'sympathy_score'.")
		return false

	if not ("detected_intent" in data) or not (data["detected_intent"] is String):
		_fail_fast("Guard payload missing string 'detected_intent'.")
		return false

	return true

func _validate_date_payload(message: Dictionary) -> bool:
	if not ("text" in message or "custom" in message):
		return true

	if not ("custom" in message):
		return true

	if not (message["custom"] is Dictionary):
		_fail_fast("Date response missing valid 'custom' payload.")
		return false

	var data: Dictionary = message["custom"]
	if not ("ease_score" in data) or not (data["ease_score"] is float or data["ease_score"] is int):
		_fail_fast("Date payload missing numeric 'ease_score'.")
		return false

	if not ("suspicion_score" in data) or not (data["suspicion_score"] is float or data["suspicion_score"] is int):
		_fail_fast("Date payload missing numeric 'suspicion_score'.")
		return false

	if not ("delta_suspicion" in data) or not (data["delta_suspicion"] is float or data["delta_suspicion"] is int):
		_fail_fast("Date payload missing numeric 'delta_suspicion'.")
		return false

	if "detected_intent" in data and not (data["detected_intent"] is String):
		_fail_fast("Date payload has invalid 'detected_intent' type.")
		return false

	if "game_event" in data and not (data["game_event"] is String):
		_fail_fast("Date payload has invalid 'game_event' type.")
		return false

	return true

func _fail_fast(reason: String) -> void:
	push_error("Chat payload contract violation: %s" % reason)
	agent_text_label.text = "[color=red]Protocol error: %s[/color]" % reason
	user_input.editable = false
	%SendButton.disabled = true
	%SendButton.visible = false
	continue_button.hide()

# --- Guard Mode Logic ---
func _end_skirmish_turn() -> void:
	# Lock input to prevent spamming
	user_input.editable = false
	%SendButton.disabled = true
	%SendButton.visible = false
	
	# Show "Return to Maze" button
	continue_button.show()
	continue_button.grab_focus()

func _handle_guard_visuals(_score: float) -> void:
	# Optional: Add visual feedback for guard score (e.g. Flash Screen Green/Red)
	pass 

# --- Date Mode Logic ---
func _update_date_meters(data: Dictionary) -> void:
	var ease_val: float = data.get("ease_score", 0.0)
	var sus_val: float = data.get("suspicion_score", 0.0)
	var delta_sus: float = data.get("delta_suspicion", 0.0)

	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(ease_bar, "value", ease_val, 0.6)
	tween.tween_property(suspicion_bar, "value", sus_val, 0.6)
	
	if delta_sus > 10.0:
		var flash = create_tween()
		agent_sprite.modulate = Color(1, 0.3, 0.3) 
		flash.tween_property(agent_sprite, "modulate", Color.WHITE, 0.3)

# --- Date Mode Event Handling ---
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
	%SendButton.visible = false
	
	# Show button with special text
	continue_button.text = "Finish Mission"
	continue_button.show()
	continue_button.grab_focus()

# --- Exit Logic (Branching) ---
func _on_continue_pressed() -> void:
	# In debug mode, just reset the UI for another round
	if debug_mode:
		user_input.editable = true
		user_input.visible = true
		%SendButton.disabled = false
		%SendButton.visible = true
		continue_button.hide()
		user_input.grab_focus()
		return
	
	if current_mode == "DATE":
		# BRANCH A: Go to Ending Screen
		get_tree().change_scene_to_file("res://stages/ending/ending_screen.tscn")
	
	elif current_mode == "CAPTAIN":
		# BRANCH B: Captain Dismissal — always raises alarm, reduces sympathy
		GameManager.last_encounter_score = 0.0
		
		# Apply negative sympathy to make the captain harder to corrupt
		var jason_name: String = GameManager.GUARD_NAME_MAP.get(current_guard_name, "")
		if jason_name != "":
			var current_delta: float = GameManager.sympathy_updates.get(jason_name, 0.0)
			GameManager.sympathy_updates[jason_name] = current_delta - 0.3
			print("Captain sympathy penalty: %s -= 0.3 (total: %s)" % [jason_name, GameManager.sympathy_updates[jason_name]])
		
		get_tree().change_scene_to_file("res://stages/maze/maze_2.tscn")
	
	else:
		# BRANCH C: Return to Maze (Guard Logic)
		GameManager.last_encounter_score = last_score
		
		if last_score > 0:
			GameManager.pacified_guards.append(current_guard_name)
		
		# Accumulate sympathy delta for the encountered guard's Jason agent
		var jason_name: String = GameManager.GUARD_NAME_MAP.get(current_guard_name, "")
		if jason_name != "":
			var current_delta: float = GameManager.sympathy_updates.get(jason_name, 0.0)
			GameManager.sympathy_updates[jason_name] = current_delta + last_score
			print("Sympathy update queued: %s += %s (total: %s)" % [jason_name, last_score, GameManager.sympathy_updates[jason_name]])

		get_tree().change_scene_to_file("res://stages/maze/maze_2.tscn")

# --- Logic Utilities ---
func _add_to_log(sender: String, text: String) -> void:
	var color: String = "white"
	if sender == "You": 
		color = "#88ccff" # Light Blue
	elif sender == "System": 
		color = "gray"
	else: 
		color = "#ffcc88" # Light Orange (Agent)
	
	log_text_label.append_text("[b][color=%s]%s:[/color][/b] %s\n" % [color, sender, text])
