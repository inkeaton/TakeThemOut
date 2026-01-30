extends Node
class_name VesnaManager

# Signals
signal command_received(intention: Dictionary)
signal connection_established()
signal connection_lost()

@export var PORT : int = 9080

var tcp_server := TCPServer.new()
var ws := WebSocketPeer.new()

# Track if we were open last frame to detect changes
var _was_open_last_frame : bool = false

func _ready() -> void:
	if tcp_server.listen(PORT) != OK:
		Warnings.print_warning("Unable to start server on port " + str(PORT), "NetworkManager")
		set_process(false)
	else:
		Messages.print_message("Listening on port " + str(PORT), "NetworkManager")

func _process(delta: float) -> void:
	# 1. Accept new TCP connections
	if tcp_server.is_connection_available():
		var conn : StreamPeerTCP = tcp_server.take_connection()
		if conn:
			# If we already have a connection, we might want to close the old one or reject the new onee
			# For now, we accept and override
			ws.accept_stream(conn)
			Messages.print_message("New TCP connection accepted. Handshaking...", "NetworkManager")

	# 2. Poll WebSocket
	ws.poll()
	var state = ws.get_ready_state()

	# 3. Handle State Changes
	if state == WebSocketPeer.STATE_OPEN:
		if not _was_open_last_frame:
			_was_open_last_frame = true
			connection_established.emit()
			Messages.print_message("WebSocket Handshake complete. Channel OPEN.", "NetworkManager")
			
		# 4. Read incoming packets (Only when OPEN)
		while ws.get_available_packet_count():
			var msg : String = ws.get_packet().get_string_from_ascii()
			
			var intention = JSON.parse_string(msg)
			if intention:
				Messages.print_json(intention, "Received Raw Message")
				command_received.emit(intention)
			else:
				Warnings.print_warning("Failed to parse JSON message", "NetworkManager")
				
	elif state == WebSocketPeer.STATE_CLOSED:
		if _was_open_last_frame:
			_was_open_last_frame = false
			connection_lost.emit()
			Warnings.print_warning("Connection lost or closed.", "NetworkManager")

# --- Helpers ---

func send_data(data: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var json_str = JSON.stringify(data)
		ws.send_text(json_str)
		Messages.print_json(data, "Sent Data")
	else:
		Warnings.print_warning("Cannot send data: WebSocket not open", "NetworkManager")

func send_signal(signal_type: String, status: String, reason: String) -> void:
	var data = {
		"sender": "body",
		"receiver": "vesna",
		"type": "signal",
		"data": {
			"type": signal_type,
			"status": status,
			"reason": reason
		}
	}
	send_data(data)

func send_sight(object_name: String, object_id: int) -> void:
	var data = {
		"sender": "body",
		"receiver": "vesna",
		"type": "sight",
		"data": {
			"sight": object_name,
			"id": object_id
		}
	}
	send_data(data)

func send_sight_with_position(object_name: String, object_id: int, position: Vector2) -> void:
	var data = {
		"sender": "body",
		"receiver": "vesna",
		"type": "sight",
		"data": {
			"sight": object_name,
			"id": object_id,
			"pos_x": position.x,
			"pos_y": position.y
		}
	}
	send_data(data)

func send_allies_found(allies: Array[String]) -> void:
	var data = {
		"sender": "body",
		"receiver": "vesna",
		"type": "allies",
		"data": {
			"allies": allies
		}
	}
	send_data(data)

func send_navigation_update(status: String, waypoint_name: String):
	var data = {
		"sender": "body",
		"receiver": "vesna", # Or specific agent name
		"type": "navigation",
		"data": {
			"status": status,
			"waypoint": waypoint_name
		}
	}
	send_data(data)

func send_custom_event(event_type: String, event_data: Dictionary) -> void:
	var data = {
		"sender": "body",
		"receiver": "vesna",
		"type": event_type,
		"data": event_data
	}
	send_data(data)

func send_event(event_type: String, event_data: Dictionary) -> void:
	"""Send an event to the mind using the 'signal' message type.
	The event_type becomes part of the data with additional event_data fields."""
	var data = {
		"sender": "body",
		"receiver": "vesna",
		"type": "signal",
		"data": event_data.duplicate()
	}
	# Add the event type to the data
	data["data"]["type"] = event_type
	send_data(data)

func is_mind_connected() -> bool:
	return ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func _exit_tree() -> void:
	ws.close()
	tcp_server.stop()
