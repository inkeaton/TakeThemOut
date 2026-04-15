## LoadingScreen: Boots external AI services and gates entry to the maze until ready.
extends Control

# --- State ---
@onready var status_label: Label = %StatusLabel
var guard_ready: bool = false
var date_ready: bool = false
var _is_polling: bool = false
var _transitioning: bool = false

# --- Lifecycle ---

func _ready() -> void:
	# 0. Kill any orphan Rasa processes left from a previous crash
	ServerManager.kill_orphans_on_ports()
	
	# 1. Trigger the startup of both Rasa bots
	ServerManager.start_guard_servers()
	ServerManager.start_date_servers() 
	
	# 2. Start Polling Loop — checks both bots
	_check_status_loop()

# --- Health Polling ---

func _check_status_loop() -> void:
	# Ping Guard Bot
	if not guard_ready:
		var http_guard = HTTPRequest.new()
		add_child(http_guard)
		http_guard.request_completed.connect(_on_guard_ping)
		http_guard.request(ServerManager.get_guard_core_base_url())
	
	# Ping Date Bot
	if not date_ready:
		var http_date = HTTPRequest.new()
		add_child(http_date)
		http_date.request_completed.connect(_on_date_ping)
		http_date.request(ServerManager.get_date_core_base_url())
	
	# If both already ready proceed immediately
	if guard_ready and date_ready:
		_proceed_to_maze()

func _on_guard_ping(_result, code, _headers, _body) -> void:
	if code == 200:
		guard_ready = true
	_try_proceed()

func _on_date_ping(_result, code, _headers, _body) -> void:
	if code == 200:
		date_ready = true
	_try_proceed()

func _try_proceed() -> void:
	if guard_ready and date_ready:
		_proceed_to_maze()
	elif not _is_polling:
		_update_status()
		# Wait and re-check whichever bot is still not ready
		_is_polling = true
		await get_tree().create_timer(2.0).timeout
		_is_polling = false
		_check_status_loop()

func _update_status() -> void:
	var parts: Array[String] = []
	if guard_ready:
		parts.append("Guard READY")
	else:
		parts.append("Guard WAIT")
	if date_ready:
		parts.append("Date READY")
	else:
		parts.append("Date WAIT")
	status_label.text = "Waiting for Rasa...  %s" % "  |  ".join(parts)

func _proceed_to_maze() -> void:
	if _transitioning:
		return
	_transitioning = true
	status_label.text = "Connection Established!"
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://stages/maze/maze_2.tscn")
