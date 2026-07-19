extends Node
## Client HTTP vers le pont Python (autoload "Bridge").
## Le jeu ne parle qu'au pont (POST /command) ; toute la logique de polling et
## de dialogue avec PTBuilder vit dans le pont. Voir CLAUDE.md section 3.

const BRIDGE := "http://127.0.0.1:8081"

## Émis quand un job déposé revient (status = "ok"/"error", data = résultat).
signal command_result(job_id: String, status: String, data)


func ping() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, _body):
		http.queue_free()
		if code == 200:
			print("[bridge] pont joignable sur %s ✓" % BRIDGE)
		else:
			push_warning("[bridge] pont injoignable (code %d) - lance bridge/server.py" % code)
	)
	var err := http.request(BRIDGE + "/health", [], HTTPClient.METHOD_GET)
	if err != OK:
		push_warning("[bridge] impossible de contacter le pont - lance bridge/server.py")


func add_device(name: String, model: String, x: int, y: int) -> void:
	_post_command({"action": "addDevice", "name": name, "model": model, "x": x, "y": y})


func add_link(dev1: String, iface1: String, dev2: String, iface2: String, cable := "straight") -> void:
	_post_command({
		"action": "addLink",
		"dev1": dev1, "iface1": iface1,
		"dev2": dev2, "iface2": iface2,
		"cable": cable,
	})


func configure_ios(name: String, commands: Array) -> void:
	_post_command({"action": "configureIos", "name": name, "commands": commands})


func get_devices() -> void:
	_post_command({"action": "getDevices"})


## Dépose une commande sur le pont et suit son résultat via /result/<job_id>.
func _post_command(cmd: Dictionary) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, body):
		http.queue_free()
		if code != 200:
			push_error("[bridge] POST /command a échoué (code %d)" % code)
			return
		var resp = JSON.parse_string(body.get_string_from_utf8())
		if typeof(resp) == TYPE_DICTIONARY and resp.has("job_id"):
			print("[bridge] job déposé : %s (%s)" % [resp["job_id"], cmd.get("action", "?")])
			_poll_result(resp["job_id"])
		else:
			push_error("[bridge] réponse inattendue du pont : %s" % body.get_string_from_utf8())
	)
	var err := http.request(
		BRIDGE + "/command",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(cmd),
	)
	if err != OK:
		http.queue_free()
		push_error("[bridge] request() a échoué (%d) - le pont tourne-t-il ?" % err)


## Interroge /result/<job_id> jusqu'à obtenir ok/error (max ~10s).
func _poll_result(job_id: String, tries := 0) -> void:
	if tries > 40:
		push_warning("[bridge] pas de résultat pour le job %s (timeout)" % job_id)
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, body):
		http.queue_free()
		if code != 200:
			return
		var resp = JSON.parse_string(body.get_string_from_utf8())
		if typeof(resp) != TYPE_DICTIONARY:
			return
		var status: String = resp.get("status", "pending")
		if status == "pending":
			await get_tree().create_timer(0.25).timeout
			_poll_result(job_id, tries + 1)
		else:
			var data = resp.get("result", resp.get("error", null))
			print("[bridge] job %s -> %s" % [job_id, status])
			command_result.emit(job_id, status, data)
	)
	http.request(BRIDGE + "/result/" + job_id, [], HTTPClient.METHOD_GET)
