## LoadingScreen: Boots external AI services and gates entry to the maze until ready.
extends Control

# --- Configuration ---
const RASA_STARTUP_TIMEOUT_SEC: float = 90.0

# --- State ---
@onready var status_label: Label = %StatusLabel
var guard_ready: bool = false
var date_ready: bool = false
var _is_polling: bool = false
var _transitioning: bool = false
var _startup_started_msec: int = 0

# --- Lifecycle ---

func _ready() -> void:
	_startup_started_msec = Time.get_ticks_msec()
	guard_ready = false
	date_ready = false
	_transitioning = false
	_is_polling = false

	# 0. Kill any orphan Rasa processes left from a previous crash
	ServerManager.kill_orphans_on_ports()
	
	# 1. Trigger the startup of both Rasa bots
	ServerManager.start_guard_servers()
	ServerManager.start_date_servers() 
	
	# 2. Start Polling Loop — checks both bots
	_check_status_loop()

# --- Health Polling ---

func _check_status_loop() -> void:
	if _has_startup_timed_out():
		_handle_startup_timeout()
		return

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
		if _has_startup_timed_out():
			_handle_startup_timeout()
			return
		_update_status()
		# Wait and re-check whichever bot is still not ready
		_is_polling = true
		await get_tree().create_timer(2.0).timeout
		_is_polling = false
		_check_status_loop()

func _update_status() -> void:
	var parts: Array[String] = []
	if guard_ready:
		parts.append("\nGuard READY")
	else:
		parts.append("\nGuard WAIT")
	if date_ready:
		parts.append("Date READY")
	else:
		parts.append("Date WAIT")
	var elapsed_sec: float = float(Time.get_ticks_msec() - _startup_started_msec) / 1000.0
	var timeout_left: int = max(0, int(ceil(RASA_STARTUP_TIMEOUT_SEC - elapsed_sec)))
	status_label.text = "Waiting for Rasa...  %s  \nTimeout in %ss" % ["  |  ".join(parts), timeout_left]

func _proceed_to_maze() -> void:
	if _transitioning:
		return
	_transitioning = true
	status_label.text = "Connection Established!"
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://stages/maze/maze_2.tscn")

func _has_startup_timed_out() -> bool:
	var elapsed_sec: float = float(Time.get_ticks_msec() - _startup_started_msec) / 1000.0
	return elapsed_sec >= RASA_STARTUP_TIMEOUT_SEC

func _handle_startup_timeout() -> void:
	if _transitioning:
		return
	_transitioning = true
	status_label.text = "Startup timeout. Rasa did not become ready in time."
	push_error("LoadingScreen timeout: Rasa services did not reach ready state.")
