extends Node
## Client HTTP vers le pont Python (autoload "Bridge").
## Le jeu ne parle qu'au pont (POST /command) ; toute la logique de polling et
## de dialogue avec PTBuilder vit dans le pont. Voir CLAUDE.md section 3.
##
## Au demarrage, tente de se connecter au pont ; s'il ne repond pas, le lance
## automatiquement (python bridge/server.py) avant de reessayer.

const BRIDGE := "http://127.0.0.1:8081"
const HEALTH_CHECK_RETRIES := 10
const HEALTH_CHECK_INTERVAL := 0.5

## Emis a chaque changement d'etat de connexion au pont.
## state: "checking" | "launching" | "connected" | "error"
signal status_changed(state: String, message: String)

## Emis quand un job depose revient (status = "ok"/"error", data = resultat).
signal command_result(job_id: String, status: String, data)

var _bridge_pid := -1
var _connected := false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_stop_spawned_bridge()


func _stop_spawned_bridge() -> void:
	if _bridge_pid != -1 and OS.is_process_running(_bridge_pid):
		OS.kill(_bridge_pid)
		_bridge_pid = -1


## Verifie que le pont repond ; le lance automatiquement sinon.
func ensure_running() -> void:
	status_changed.emit("checking", "Recherche du pont...")
	_check_health(0)


func _check_health(attempt: int) -> void:
	var http := HTTPRequest.new()
	http.timeout = 2.0
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, _body):
		http.queue_free()
		if code == 200:
			_connected = true
			status_changed.emit("connected", "Pont connecte sur %s" % BRIDGE)
			return
		_on_health_check_failed(attempt)
	)
	var err := http.request(BRIDGE + "/health", [], HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		_on_health_check_failed(attempt)


func _on_health_check_failed(attempt: int) -> void:
	if attempt == 0:
		_spawn_bridge()
	if attempt >= HEALTH_CHECK_RETRIES:
		status_changed.emit(
			"error",
			"Pont introuvable. Lance-le a la main : python bridge/server.py"
		)
		return
	status_changed.emit("launching", "Demarrage du pont...")
	await get_tree().create_timer(HEALTH_CHECK_INTERVAL).timeout
	_check_health(attempt + 1)


func _spawn_bridge() -> void:
	# globalize_path("res://") renvoie ".../game/" (avec slash final). On enleve ce
	# slash avant get_base_dir(), sinon il ne remonte pas au parent du dossier game/.
	var game_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var project_root := game_dir.get_base_dir()
	var server_script := project_root.path_join("bridge/server.py")
	if not FileAccess.file_exists(server_script):
		push_error("[bridge] server.py introuvable : %s" % server_script)
		status_changed.emit(
			"error",
			"bridge/server.py introuvable. Lance-le a la main : python bridge/server.py"
		)
		return
	# On passe par cmd.exe pour beneficier de la meme resolution de PATH qu'un
	# terminal normal (OS.create_process ne cherche pas "python" dans le PATH
	# de la meme facon, et peut echouer silencieusement si plusieurs Python
	# sont installes).
	var pid := OS.create_process("cmd.exe", ["/c", "python", server_script], false)
	if pid == -1:
		status_changed.emit(
			"error",
			"Impossible de lancer python. Verifie qu'il est installe et sur le PATH."
		)
		return
	_bridge_pid = pid


## Vide la topologie Packet Tracer (equivalent File > New). Utilise avant de
## rejouer une sauvegarde ou de demarrer une nouvelle partie, pour partir propre.
func clear_topology() -> void:
	_post_command({"action": "clearTopology"})


func add_device(device_name: String, model: String, x: int, y: int) -> void:
	_post_command({"action": "addDevice", "name": device_name, "model": model, "x": x, "y": y})


func add_link(dev1: String, iface1: String, dev2: String, iface2: String, cable := "straight") -> void:
	_post_command({
		"action": "addLink",
		"dev1": dev1, "iface1": iface1,
		"dev2": dev2, "iface2": iface2,
		"cable": cable,
	})


func configure_ios(device_name: String, commands: Array) -> void:
	_post_command({"action": "configureIos", "name": device_name, "commands": commands})


func get_devices() -> void:
	_post_command({"action": "getDevices"})


## Tape une commande dans le vrai CLI de l'equipement (voir bridge/README.md
## "Real interactive CLI access"). on_result(status, data) est appele quand
## la commande a ete transmise (data=true), pas quand elle a fini de s'executer
## dans PT (un ping prend plusieurs secondes) - relire via cli_read() ensuite.
## delay_before (secondes) : utile au rejeu d'une sauvegarde, pour laisser un
## equipement fraichement recree finir de booter avant sa premiere commande.
func cli_send(device_name: String, command: String, on_result: Callable = Callable(), delay_before: float = 0.0) -> void:
	var cmd := {"action": "cliSend", "name": device_name, "command": command}
	if delay_before > 0.0:
		cmd["delay_before"] = delay_before
	_post_command(cmd, on_result)


## Lit l'etat courant du CLI d'un equipement. on_result(status, data) recoit
## data = {"output": <transcript complet>, "prompt": <prompt courant>}.
func cli_read(device_name: String, on_result: Callable) -> void:
	_post_command({"action": "cliRead", "name": device_name}, on_result)


## Depose une commande sur le pont et suit son resultat via /result/<job_id>.
## on_result(status, data), si fourni, est appele en plus du signal command_result
## (utile pour des appelants qui doivent distinguer leurs propres requetes,
## comme le terminal en jeu qui peut interroger plusieurs equipements).
func _post_command(cmd: Dictionary, on_result: Callable = Callable()) -> void:
	if not _connected:
		push_warning("[bridge] commande ignoree, pont non connecte : %s" % cmd.get("action", "?"))
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, body):
		http.queue_free()
		if code != 200:
			push_error("[bridge] POST /command a echoue (code %d)" % code)
			return
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("job_id"):
			var resp := parsed as Dictionary
			var job_id := resp["job_id"] as String
			_poll_result(job_id, 0, on_result)
		else:
			push_error("[bridge] reponse inattendue du pont : %s" % body.get_string_from_utf8())
	)
	var err := http.request(
		BRIDGE + "/command",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(cmd),
	)
	if err != OK:
		http.queue_free()
		push_error("[bridge] request() a echoue (%d) - le pont tourne-t-il ?" % err)


## Interroge /result/<job_id> jusqu'a obtenir ok/error (max ~10s).
func _poll_result(job_id: String, tries := 0, on_result: Callable = Callable()) -> void:
	if tries > 40:
		push_warning("[bridge] pas de resultat pour le job %s (timeout)" % job_id)
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, body):
		http.queue_free()
		if code != 200:
			return
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			return
		var resp := parsed as Dictionary
		var status := resp.get("status", "pending") as String
		if status == "pending":
			await get_tree().create_timer(0.25).timeout
			_poll_result(job_id, tries + 1, on_result)
		else:
			var data: Variant = resp.get("result", resp.get("error", null))
			command_result.emit(job_id, status, data)
			if on_result.is_valid():
				on_result.call(status, data)
	)
	http.request(BRIDGE + "/result/" + job_id, [], HTTPClient.METHOD_GET)
