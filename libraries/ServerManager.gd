extends Node

# --- CONFIGURATION ---
# We use globalize_path to get the absolute OS path (e.g. C:/Users/.../tongue/skirmish)

var SKIRMISH_BOT_PATH: String = ProjectSettings.globalize_path("res://tongue/skirmish")
var DATE_BOT_PATH: String  = ProjectSettings.globalize_path("res://tongue/date")
var MIND_PATH: String = ProjectSettings.globalize_path("res://mind")

# Path to the Python executable
var VENV_PATH_WIN: String = ProjectSettings.globalize_path("res://tongue/venv/Scripts/python.exe")
var VENV_PATH_UNIX: String = ProjectSettings.globalize_path("res://tongue/venv/bin/python")

# Log directory for server output (user://logs/ → ~/.local/share/godot/.../logs/)
var LOG_DIR: String = ProjectSettings.globalize_path("user://logs")

# --- SIGNALS ---
signal jason_service_ready() # Emitted when Java connects to 9200

# --- STATE ---
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
	if is_jason_ready:
		return  # Already ready, stop polling
	
	# 1. Accept new TCP connections and upgrade to WebSocket
	if readiness_server.is_listening() and readiness_server.is_connection_available():
		var conn = readiness_server.take_connection()
		if conn:
			readiness_ws.accept_stream(conn)
			print("ServerManager: TCP connection on 9200, upgrading to WebSocket...")
	
	# 2. Poll the WebSocket peer
	readiness_ws.poll()
	var state = readiness_ws.get_ready_state()
	
	# 3. Handle WebSocket open (connection established)
	if state == WebSocketPeer.STATE_OPEN:
		if not _readiness_ws_connected:
			_readiness_ws_connected = true
			print("ServerManager: WebSocket handshake on 9200 complete.")
		
		# 4. Read incoming packets — wait for signal_ready message
		while readiness_ws.get_available_packet_count():
			var msg: String = readiness_ws.get_packet().get_string_from_ascii()
			var parsed = JSON.parse_string(msg)
			if parsed and parsed is Dictionary and parsed.get("type", "") == "signal_ready":
				print("JASON MIND READY! signal_ready received from '%s'." % parsed.get("sender", "unknown"))
				is_jason_ready = true
				jason_service_ready.emit()
				# Keep WebSocket open — director stays connected
				readiness_server.stop()  # No longer need to accept new connections
				return
	
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

# --- JASON (GRADLE) COMMANDS ---

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
		cmd = "cmd"
		args = ["/C", "cd /d %s && gradlew run" % MIND_PATH]
	else:
		cmd = "bash"
		args = ["-c", "cd '%s' && exec gradle run" % MIND_PATH]
	
	pids.jason_mind = OS.create_process(cmd, args, false) # true = open console for debug
	print("Spawned Jason Mind (PID: %s)" % pids.jason_mind)

func stop_jason_server() -> void:
	if pids.jason_mind != -1:
		print("Stopping Jason Mind...")
		OS.kill(pids.jason_mind)
		pids.jason_mind = -1
	# Clean up readiness state
	is_jason_ready = false
	_readiness_ws_connected = false
	readiness_ws.close()
	readiness_server.stop()

# --- START COMMANDS ---

func start_guard_servers() -> void:
	print("--- Starting Skirmish (Guard) Servers ---")
	print("Working Dir: ", SKIRMISH_BOT_PATH)
	
	# 1. Start Rasa Core (Port 5005)
	pids.guard_core = _spawn_rasa_process(SKIRMISH_BOT_PATH, ["run", "--enable-api", "--cors", "*", "--port", "5005"])
	
	# 2. Start Action Server (Port 5055)
	pids.guard_action = _spawn_rasa_process(SKIRMISH_BOT_PATH, ["run", "actions", "--port", "5055"])

func start_date_servers() -> void:
	print("--- Starting Date (Eugenia) Servers ---")
	print("Working Dir: ", DATE_BOT_PATH)
	
	# 1. Start Rasa Core (Port 5006)
	pids.date_core = _spawn_rasa_process(DATE_BOT_PATH, ["run", "--enable-api", "--cors", "*", "--port", "5006"])
	
	# 2. Start Action Server (Port 5056)
	pids.date_action = _spawn_rasa_process(DATE_BOT_PATH, ["run", "actions", "--port", "5056"])

# --- PROCESS SPAWNER ---

func _spawn_rasa_process(working_dir: String, args: Array) -> int:
	# We run python via bash, cd-ing into the bot directory first.
	var executable = ""
	var final_args = []
	
	# Build a log filename from the args (e.g. "rasa_run_5005.log")
	var log_name = "rasa_%s.log" % "_".join(args).replace("--", "").replace(" ", "")
	var log_path = LOG_DIR.path_join(log_name)
	
	if OS.get_name() == "Windows":
		executable = "cmd"
		var rasa_cmd = "%s -m rasa %s" % [VENV_PATH_WIN, " ".join(args)]
		final_args = ["/C", "cd /d %s && %s > \"%s\" 2>&1" % [working_dir, rasa_cmd, log_path]]
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

# --- STOP COMMANDS ---

func stop_all_servers() -> void:
	print("--- Stopping All Servers ---")
	for key in pids:
		var pid = pids[key]
		if pid != -1:
			print("Killing %s (PID: %s)" % [key, pid])
			OS.kill(pid)
			pids[key] = -1

# --- ORPHAN CLEANUP ---
# Kill any leftover processes on Rasa ports from a previous crash/forced exit
func kill_orphans_on_ports(ports: Array = [5005, 5006, 5055, 5056]) -> void:
	if OS.get_name() == "Windows":
		return # fuser not available on Windows
	print("--- Cleaning up orphan processes on ports %s ---" % str(ports))
	for port in ports:
		# fuser -k sends SIGKILL to any process listening on the port
		OS.execute("fuser", ["-k", "%s/tcp" % port])
	print("--- Orphan cleanup done ---")

# --- HEALTH CHECK ---

func check_server_health(port: int = 5005, callback: Callable = Callable()) -> void:
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
	http.request("http://localhost:%s" % port)
