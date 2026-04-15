## ServerManager: Orchestrates Rasa and Jason service lifecycle for the game runtime.
extends Node

# --- Configuration ---
# Rasa connection config (single source of truth).
const RASA_HOST: String = "localhost"
const GUARD_CORE_PORT: int = 8005
const DATE_CORE_PORT: int = 8006
const GUARD_ACTION_PORT: int = 8055
const DATE_ACTION_PORT: int = 8056

# We use globalize_path to get the absolute OS path (e.g. /home/.../tongue/skirmish)

var SKIRMISH_BOT_PATH: String = ProjectSettings.globalize_path("res://tongue/skirmish")
var DATE_BOT_PATH: String  = ProjectSettings.globalize_path("res://tongue/date")
var MIND_PATH: String = ProjectSettings.globalize_path("res://mind")

# Path to the Python executable
var VENV_PATH_WIN: String = ProjectSettings.globalize_path("res://tongue/venv/Scripts/python.exe")
var VENV_PATH_UNIX: String = ProjectSettings.globalize_path("res://tongue/venv/bin/python")

# Log directory for server output (user://logs/ → ~/.local/share/godot/.../logs/)
var LOG_DIR: String = ProjectSettings.globalize_path("res://logs/")

# --- Signals ---
signal jason_service_ready() # Emitted when Java connects to 9200

# --- State ---
var pids: Dictionary = {
	"guard_core": -1, "guard_action": -1,
	"date_core": -1, "date_action": -1,
	"jason_mind": -1 # <--- NEW
}

var readiness_server: TCPServer = TCPServer.new()
var readiness_ws: WebSocketPeer = WebSocketPeer.new()
var is_jason_ready: bool = false
var _readiness_ws_connected: bool = false
const READY_PORT: int = 9200

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Must keep running while tree is paused
	get_tree().set_auto_accept_quit(false)
	# Ensure log directory exists
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	# Start listening for the "I am Ready" signal from Java
	if readiness_server.listen(READY_PORT) != OK:
		printerr("CRITICAL: ServerManager could not listen on port %s" % READY_PORT)
	else:
		print("ServerManager: Listening for Jason readiness on port %s" % READY_PORT)

func _process(_delta: float) -> void:
	# --- Readiness WebSocket Handling ---
	
	# 1. Accept new TCP connections and upgrade to WebSocket
	if not is_jason_ready and readiness_server.is_listening() and readiness_server.is_connection_available():
		var conn = readiness_server.take_connection()
		if conn:
			readiness_ws.accept_stream(conn)
			print("ServerManager: TCP connection on 9200, upgrading to WebSocket...")
	
	# 2. Poll the WebSocket peer (must keep polling even after ready to flush outgoing packets)
	readiness_ws.poll()
	var state = readiness_ws.get_ready_state()
	
	# 3. Handle WebSocket open (connection established)
	if state == WebSocketPeer.STATE_OPEN:
		if not _readiness_ws_connected:
			_readiness_ws_connected = true
			print("ServerManager: WebSocket handshake on 9200 complete.")
		
		# 4. Read incoming packets
		while readiness_ws.get_available_packet_count():
			var msg: String = readiness_ws.get_packet().get_string_from_ascii()
			var parsed = JSON.parse_string(msg)
			if parsed and parsed is Dictionary and parsed.get("type", "") == "signal_ready":
				print("JASON MIND READY! signal_ready received from '%s'." % parsed.get("sender", "unknown"))
				is_jason_ready = true
				jason_service_ready.emit()
				# Keep WebSocket open — director stays connected
				readiness_server.stop()  # No longer need to accept new connections
	
	# 5. Handle unexpected close
	elif state == WebSocketPeer.STATE_CLOSED and _readiness_ws_connected:
		_readiness_ws_connected = false
		print("ServerManager: WebSocket on 9200 closed unexpectedly.")

func _exit_tree() -> void:
	# Safety net: ensures servers are killed on ANY exit path
	# (programmatic quit, scene tree shutdown, etc.)
	stop_all_servers()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop_all_servers()
		get_tree().quit()

# --- Jason (Gradle) Commands ---

func start_jason_server() -> void:
	if pids.jason_mind != -1:
		print("Jason server already running.")
		return

	print("--- Starting Jason Mind (Gradle) ---")
	print("Working Dir: ", MIND_PATH)
	is_jason_ready = false # Reset status
	_readiness_ws_connected = false
	
	# Re-open the readiness listener (may have been stopped by a previous stop_jason_server)
	if not readiness_server.is_listening():
		if readiness_server.listen(READY_PORT) != OK:
			printerr("CRITICAL: Could not re-listen on port %s" % READY_PORT)
		else:
			print("ServerManager: Listening for Jason readiness on port %s" % READY_PORT)
	
	# We wrap the gradle command in a shell that cd's to the mind directory first.
	var cmd = ""
	var args = []
	
	if OS.get_name() == "Windows":
		var gradle_wrapper_win: String = MIND_PATH.path_join("gradlew.bat")
		var gradle_exec: String = "gradle"
		if FileAccess.file_exists(gradle_wrapper_win):
			gradle_exec = _quote_windows_path(gradle_wrapper_win)
		cmd = "cmd"
		args = ["/C", "cd /d %s && %s run" % [_quote_windows_path(MIND_PATH), gradle_exec]]
	else:
		cmd = "bash"
		args = ["-c", "cd '%s' && exec gradle run" % MIND_PATH]

	print("Jason launch command: %s %s" % [cmd, str(args)])
	
	pids.jason_mind = OS.create_process(cmd, args, false) # true = open console for debug
	if pids.jason_mind == -1:
		printerr("CRITICAL: Failed to spawn Jason Mind process.")
	else:
		print("Spawned Jason Mind (PID: %s)" % pids.jason_mind)

func stop_jason_server() -> void:
	if pids.jason_mind != -1:
		print("Stopping Jason Mind...")
		_terminate_pid(pids.jason_mind)
		pids.jason_mind = -1
	# Clean up readiness state
	is_jason_ready = false
	_readiness_ws_connected = false
	readiness_ws.close()
	readiness_server.stop()

# --- Start Commands ---

func start_guard_servers() -> void:
	print("--- Starting Skirmish (Guard) Servers ---")
	print("Working Dir: ", SKIRMISH_BOT_PATH)
	
	# 1. Start Rasa Core
	pids.guard_core = _spawn_rasa_process(SKIRMISH_BOT_PATH, ["run", "--enable-api", "--cors", "*", "--port", str(GUARD_CORE_PORT)])
	
	# 2. Start Action Server
	pids.guard_action = _spawn_rasa_process(SKIRMISH_BOT_PATH, ["run", "actions", "--port", str(GUARD_ACTION_PORT)])

func start_date_servers() -> void:
	print("--- Starting Date (Eugenia) Servers ---")
	print("Working Dir: ", DATE_BOT_PATH)
	
	# 1. Start Rasa Core
	pids.date_core = _spawn_rasa_process(DATE_BOT_PATH, ["run", "--enable-api", "--cors", "*", "--port", str(DATE_CORE_PORT)])
	
	# 2. Start Action Server
	pids.date_action = _spawn_rasa_process(DATE_BOT_PATH, ["run", "actions", "--port", str(DATE_ACTION_PORT)])

# --- Process Spawner ---

func _spawn_rasa_process(working_dir: String, args: Array) -> int:
	# We run python via bash, cd-ing into the bot directory first.
	var executable = ""
	var final_args = []
	
	# Build a log filename from the args (e.g. "rasa_run_5005.log")
	var log_name = "rasa_%s.log" % "_".join(args).replace("--", "").replace(" ", "")
	var log_path = LOG_DIR.path_join(log_name)
	
	if OS.get_name() == "Windows":
		executable = "cmd"
		if not FileAccess.file_exists(VENV_PATH_WIN):
			printerr("CRITICAL: Windows Python venv not found at: %s" % VENV_PATH_WIN)
		var rasa_cmd = "%s -m rasa %s" % [_quote_windows_path(VENV_PATH_WIN), " ".join(args)]
		final_args = ["/C", "cd /d %s && %s > %s 2>&1" % [_quote_windows_path(working_dir), rasa_cmd, _quote_windows_path(log_path)]]
	else:
		# Unix: exec replaces bash so PID = real process; redirect output to log
		executable = "bash"
		var rasa_cmd = "%s -m rasa %s" % [VENV_PATH_UNIX, " ".join(args)]
		final_args = ["-c", "cd '%s' && exec %s >> '%s' 2>&1" % [working_dir, rasa_cmd, log_path]]
	
	print("Rasa log: ", log_path)
	
	# open_console = false so the tracked PID is the actual Rasa process, not a terminal wrapper
	var pid = OS.create_process(executable, final_args, false)
	
	if pid == -1:
		printerr("CRITICAL: Failed to spawn process in ", working_dir)
		printerr("Check if Python path is correct: ", executable)
	else:
		print("Spawned PID %s in %s" % [pid, working_dir])
		
	return pid

# --- Director Communication ---
# Send a JSON message to the director (ready_agent) over the port 9200 WebSocket
func send_to_director(data: Dictionary) -> void:
	if readiness_ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var json_str = JSON.stringify(data)
		readiness_ws.send_text(json_str)
		print("ServerManager: Sent to director: ", json_str)
	else:
		printerr("ServerManager: Cannot send to director — WebSocket not open.")

# --- Stop Commands ---

func stop_all_servers() -> void:
	print("--- Stopping All Servers ---")
	for key in pids:
		var pid = pids[key]
		if pid != -1:
			print("Killing %s (PID: %s)" % [key, pid])
			_terminate_pid(pid)
			pids[key] = -1

# --- Orphan Cleanup ---
# Kill any leftover processes on Rasa ports from a previous crash/forced exit
func kill_orphans_on_ports(ports: Array = []) -> void:
	if ports.is_empty():
		ports = get_rasa_ports()
	if OS.get_name() == "Windows":
		print("--- Cleaning up orphan processes on Windows ports %s ---" % str(ports))
		for port in ports:
			var ps_cmd := "Get-NetTCPConnection -LocalPort %d -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess | Sort-Object -Unique | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }" % int(port)
			OS.execute("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps_cmd])
		print("--- Windows orphan cleanup done ---")
		return
	print("--- Cleaning up orphan processes on ports %s ---" % str(ports))
	for port in ports:
		# fuser -k sends SIGKILL to any process listening on the port
		OS.execute("fuser", ["-k", "%s/tcp" % port])
	print("--- Orphan cleanup done ---")

# --- Health Check ---

func check_server_health(port: int = GUARD_CORE_PORT, callback: Callable = Callable()) -> void:
	var http = HTTPRequest.new()
	add_child(http)
	
	http.request_completed.connect(func(_res, code, _head, _body): 
		if code == 200:
			print("Server on port %s is READY." % port)
			if callback.is_valid(): callback.call(true)
		else:
			print("Server on port %s is NOT READY (Code: %s)." % [port, code])
			if callback.is_valid(): callback.call(false)
		http.queue_free()
	)
	
	# Rasa's health check endpoint is simply the root URL
	http.request(_build_rasa_core_base_url(port))

# --- Rasa URL Helpers ---

func get_guard_webhook_url() -> String:
	return _build_rasa_webhook_url(GUARD_CORE_PORT)

func get_date_webhook_url() -> String:
	return _build_rasa_webhook_url(DATE_CORE_PORT)

func get_guard_core_base_url() -> String:
	return _build_rasa_core_base_url(GUARD_CORE_PORT)

func get_date_core_base_url() -> String:
	return _build_rasa_core_base_url(DATE_CORE_PORT)

func get_rasa_ports() -> Array:
	return [GUARD_CORE_PORT, DATE_CORE_PORT, GUARD_ACTION_PORT, DATE_ACTION_PORT]

func _build_rasa_core_base_url(port: int) -> String:
	return "http://%s:%d" % [RASA_HOST, port]

func _build_rasa_webhook_url(port: int) -> String:
	return "http://%s:%d/webhooks/rest/webhook" % [RASA_HOST, port]

func _terminate_pid(pid: int) -> void:
	if pid == -1:
		return
	if OS.get_name() == "Windows":
		OS.execute("taskkill", ["/PID", str(pid), "/T", "/F"])
	else:
		OS.kill(pid)

func _quote_windows_path(path: String) -> String:
	return "\"%s\"" % path
