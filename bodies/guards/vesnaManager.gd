## VesnaManager: Body-side WebSocket bridge used by guard agents to communicate with the mind.
## Role: utility
## Responsibilities:
## - Accept and maintain local WebSocket connection with Jason mind agent.
## - Emit incoming command dictionaries to body scripts.
## - Send typed perception/event/navigation payloads to the mind.
## Dependencies:
## - `TCPServer` and `WebSocketPeer`.
## - `Messages` and `Warnings` logging utilities.
extends Node
class_name VesnaManager

# --- Signals ---
signal command_received(intention: Dictionary)
signal connection_established()
signal connection_lost()

# --- Configuration ---
@export var PORT : int = 9080

# --- State ---
var tcp_server := TCPServer.new()
var ws := WebSocketPeer.new()

# Track if we were open last frame to detect changes
var _was_open_last_frame : bool = false

# --- Lifecycle ---
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Must keep running while tree is paused
	if tcp_server.listen(PORT) != OK:
		Warnings.print_warning("Unable to start server on port " + str(PORT), "NetworkManager")
		set_process(false)
	else:
		Messages.print_message("Listening on port " + str(PORT), "NetworkManager")

# --- Connection Polling ---
func _process(_delta: float) -> void:
	# 1. Accept new TCP connections.
	if tcp_server.is_connection_available():
		var conn : StreamPeerTCP = tcp_server.take_connection()
		if conn:
			# If a prior connection exists, accept and override with the new one.
			ws.accept_stream(conn)
			Messages.print_message("New TCP connection accepted. Handshaking...", "NetworkManager")

	# 2. Poll WebSocket.
	ws.poll()
	var state = ws.get_ready_state()

	# 3. Handle state changes.
	if state == WebSocketPeer.STATE_OPEN:
		if not _was_open_last_frame:
			_was_open_last_frame = true
			connection_established.emit()
			Messages.print_message("WebSocket Handshake complete. Channel OPEN.", "NetworkManager")
			
		# 4. Read incoming packets (only when open).
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

# --- Outbound Message Helpers ---

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
		"receiver": "vesna", # Can be refined to a specific agent name when needed.
		"type": "navigation",
		"data": {
			"status": status,
			"waypoint": waypoint_name
		}
	}
	send_data(data)

func send_target_lost(position: Vector2, reason: String) -> void:
	var data = {
		"sender": "body",
		"receiver": "vesna",
		"type": "event",
		"data": {
			"event": "target_lost",
			"pos_x": position.x,
			"pos_y": position.y,
			"reason": reason
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

## Sends an event to the mind using `signal` message type.
## `event_type` is injected into the outgoing `data` payload.
func send_event(event_type: String, event_data: Dictionary) -> void:
	var data = {
		"sender": "body",
		"receiver": "vesna",
		"type": "signal",
		"data": event_data.duplicate()
	}
	# Add the event type to the data.
	data["data"]["type"] = event_type
	send_data(data)

# --- Connection Status ---

func is_mind_connected() -> bool:
	return ws.get_ready_state() == WebSocketPeer.STATE_OPEN

# --- Cleanup ---
func _exit_tree() -> void:
	ws.close()
	tcp_server.stop()
