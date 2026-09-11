"""Service local entre Godot et le moteur de simulation ns-3."""
import os
import subprocess
import tempfile
import threading
import uuid
from pathlib import Path
from flask import Flask, jsonify, request

app = Flask(__name__)
lock = threading.Lock()
results = {}
PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_NS3_DIR = PROJECT_ROOT.parent / "ns-3"


def ns3_dir():
    return Path(os.environ.get("BACKBONE_NS3_DIR", DEFAULT_NS3_DIR))


def run_lab(configure_routes=True):
    root = ns3_dir()
    executable = root / "build" / "scratch" / "ns3.47-backbone-routed-lab"
    if not executable.is_file():
        raise RuntimeError("Moteur ns-3 introuvable dans " + str(root))
    completed = subprocess.run(
        [str(executable), f"--configureRoutes={'true' if configure_routes else 'false'}"],
        cwd=root, capture_output=True, text=True, timeout=20, check=False,
    )
    output = (completed.stdout + completed.stderr).strip()
    return {"success": "PING REUSSI" in output, "output": output}


def clean(value):
    return str(value).replace("\t", " ").replace("\n", " ")


def run_topology(payload):
    root = ns3_dir()
    executable = root / "build" / "scratch" / "ns3.47-backbone-engine"
    if not executable.is_file():
        raise RuntimeError("Moteur dynamique ns-3 introuvable dans " + str(root))

    topology = payload.get("topology", {})
    lines = []
    for device in topology.get("devices", []):
        name = clean(device.get("name", ""))
        lines.append(f"DEVICE\t{name}\t{clean(device.get('category', 'router'))}")
        for iface, state in device.get("interfaces", {}).items():
            status = "down" if state.get("shutdown", True) else "up"
            lines.append(f"IFACE\t{name}\t{clean(iface)}\t{clean(state.get('address', ''))}\t{status}")
        for route in device.get("routes", []):
            lines.append(
                f"ROUTE\t{name}\t{clean(route.get('network', ''))}\t{clean(route.get('next_hop', ''))}"
            )
    for link in topology.get("links", []):
        lines.append(
            "LINK\t{}\t{}\t{}\t{}".format(
                clean(link.get("dev1", "")), clean(link.get("iface1", "")),
                clean(link.get("dev2", "")), clean(link.get("iface2", "")),
            )
        )
    lines.append(f"PING\t{clean(payload.get('source', ''))}\t{clean(payload.get('destination', ''))}")

    path = None
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".topology", delete=False) as scenario:
            scenario.write("\n".join(lines) + "\n")
            path = scenario.name
        completed = subprocess.run(
            [str(executable), f"--scenario={path}"], cwd=root,
            capture_output=True, text=True, timeout=20, check=False,
        )
        output = (completed.stdout + completed.stderr).strip()
        return {"success": "PING REUSSI" in output, "output": output}
    finally:
        if path:
            Path(path).unlink(missing_ok=True)


def execute_job(job_id, command):
    try:
        action = command.get("action")
        if action == "runRoutedLab":
            value = run_lab(bool(command.get("configure_routes", True)))
        elif action == "ping":
            value = run_topology(command)
        else:
            raise ValueError("action inconnue: " + str(action))
        result = {"status": "ok", "result": value}
    except Exception as error:
        result = {"status": "error", "error": str(error)}
    with lock:
        results[job_id] = result


@app.after_request
def cors(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    return response


@app.get("/health")
def health():
    return jsonify({"ok": True, "engine": "ns-3", "ns3_dir": str(ns3_dir())})


@app.post("/command")
def command():
    job_id = uuid.uuid4().hex
    with lock:
        results[job_id] = {"status": "pending"}
    threading.Thread(
        target=execute_job, args=(job_id, request.get_json(force=True)), daemon=True
    ).start()
    return jsonify({"job_id": job_id})


@app.get("/result/<job_id>")
def result(job_id):
    with lock:
        value = results.get(job_id)
    if value is None:
        return jsonify({"error": "job inconnu"}), 404
    return jsonify(value)


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8081, threaded=True)
