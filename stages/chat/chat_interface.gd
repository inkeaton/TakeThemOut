extends Control

# Rasa Endpoint
const RASA_URL = "http://localhost:5005/webhooks/rest/webhook"

# Using % ensures Godot finds these nodes even if you move them into containers later
@onready var chat_log = $VBoxContainer/ChatLog
@onready var input_box = $VBoxContainer/InputBox
@onready var send_button = $VBoxContainer/SendButton
@onready var http_request = $RasaRequest

func _ready():
	# SAFETY CHECK: Only connect if the node actually exists
	if http_request == null:
		printerr("CRITICAL ERROR: HTTPRequest node not found! Make sure you added it and set it as Unique Name (%)")
		return
	
	send_button.pressed.connect(_on_send_pressed)
	input_box.text_submitted.connect(_on_send_pressed)
	http_request.request_completed.connect(_on_request_completed)
	
	add_message("System", "Ready to chat.", Color.GREEN)

func _on_send_pressed(text_submitted = ""):
	var user_text = input_box.text.strip_edges()
	if user_text.is_empty():
		return

	input_box.text = "" 
	add_message("You", user_text, Color.CYAN)
	_send_to_rasa(user_text)

func _send_to_rasa(text_to_send: String):
	var data = { "sender": "godot_player", "message": text_to_send }
	var json_payload = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]
	
	# Godot 4.6 HTTPRequest syntax
	http_request.request(RASA_URL, headers, HTTPClient.METHOD_POST, json_payload)

func _on_request_completed(result, response_code, headers, body):
	if response_code != 200:
		add_message("System", "Error: %s" % response_code, Color.RED)
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result == OK:
		var response_array = json.get_data()
		if response_array is Array:
			for message in response_array:
				if "text" in message:
					add_message("Bot", message["text"], Color.WHITE)

func add_message(sender: String, text: String, color: Color):
	var hex_color = color.to_html()
	chat_log.append_text("[b][color=#%s]%s:[/color][/b] %s\n" % [hex_color, sender, text])
