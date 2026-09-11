extends Node
## Client HTTP vers le moteur local ns-3 (autoload "Bridge").

const BRIDGE := "http://127.0.0.1:8081"
const HEALTH_CHECK_RETRIES := 10
const HEALTH_CHECK_INTERVAL := 0.5

signal status_changed(state: String, message: String)
signal command_result(job_id: String, status: String, data)

var _bridge_pid := -1
var _connected := false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_stop_spawned_bridge()

func _stop_spawned_bridge() -> void:
	if _bridge_pid != -1 and OS.is_process_running(_bridge_pid): OS.kill(_bridge_pid)
	_bridge_pid = -1

func ensure_running() -> void:
	status_changed.emit("checking", "Recherche du moteur ns-3...")
	_check_health(0)

func _check_health(attempt: int) -> void:
	var http := HTTPRequest.new()
	http.timeout = 2.0
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, _body):
		http.queue_free()
		if code == 200:
			_connected = true
			status_changed.emit("connected", "Moteur ns-3 connecte")
			return
		_on_health_check_failed(attempt)
	)
	var err := http.request(BRIDGE + "/health", [], HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		_on_health_check_failed(attempt)

func _on_health_check_failed(attempt: int) -> void:
	if attempt == 0: _spawn_bridge()
	if attempt >= HEALTH_CHECK_RETRIES:
		status_changed.emit("error", "Moteur introuvable. Lance : python3 bridge/server.py")
		return
	status_changed.emit("launching", "Demarrage du moteur ns-3...")
	await get_tree().create_timer(HEALTH_CHECK_INTERVAL).timeout
	_check_health(attempt + 1)

func _spawn_bridge() -> void:
	var game_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var project_root := game_dir.get_base_dir()
	var server_script := project_root.path_join("bridge/server.py")
	var venv_python := project_root.path_join("bridge/.venv/bin/python")
	var python := venv_python if FileAccess.file_exists(venv_python) else "python3"
	if not FileAccess.file_exists(server_script):
		status_changed.emit("error", "bridge/server.py introuvable")
		return
	if not OS.get_environment("FLATPAK_ID").is_empty():
		_bridge_pid = OS.create_process("flatpak-spawn", ["--host", python, server_script], false)
	else:
		_bridge_pid = OS.create_process(python, [server_script], false)
	if _bridge_pid == -1: status_changed.emit("error", "Impossible de lancer le moteur Python")

func run_routed_lab(configure_routes: bool, on_result: Callable) -> void:
	_post_command({"action": "runRoutedLab", "configure_routes": configure_routes}, on_result)

func ping(source: String, destination: String, topology: Dictionary, on_result: Callable) -> void:
	_post_command({
		"action": "ping",
		"source": source,
		"destination": destination,
		"topology": topology,
	}, on_result)

func _post_command(cmd: Dictionary, on_result: Callable = Callable()) -> void:
	if not _connected:
		if on_result.is_valid(): on_result.call("error", "Moteur non connecte")
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, body):
		http.queue_free()
		if code != 200:
			if on_result.is_valid(): on_result.call("error", "Erreur HTTP %d" % code)
			return
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("job_id"):
			_poll_result(str(parsed["job_id"]), 0, on_result)
	)
	http.request(BRIDGE + "/command", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(cmd))

func _poll_result(job_id: String, tries: int, on_result: Callable) -> void:
	if tries > 80:
		if on_result.is_valid(): on_result.call("error", "Delai depasse")
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, body):
		http.queue_free()
		if code != 200: return
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY: return
		var status := str(parsed.get("status", "pending"))
		if status == "pending":
			await get_tree().create_timer(0.25).timeout
			_poll_result(job_id, tries + 1, on_result)
		else:
			var data: Variant = parsed.get("result", parsed.get("error", null))
			command_result.emit(job_id, status, data)
			if on_result.is_valid(): on_result.call(status, data)
	)
	http.request(BRIDGE + "/result/" + job_id, [], HTTPClient.METHOD_GET)
