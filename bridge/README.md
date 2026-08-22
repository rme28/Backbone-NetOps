# Godot to ns-3 Bridge

This local service launches the ns-3 network simulation engine and returns its results to Godot.

## Setup

```bash
cd bridge
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python server.py
```

By default, the bridge looks for ns-3 in an `ns-3` directory next to the project directory. Set `BACKBONE_NS3_DIR` to use another location.

The service listens on `127.0.0.1:8081`. It remains local and does not require a remote service.

## Endpoints

- `GET /health`: checks whether the bridge and compiled engine are available
- `POST /command`: submits a simulation command
- `GET /result/<job_id>`: returns a pending, successful, or failed result

## Dynamic Simulation Action

Godot sends the current devices, exact interfaces, cables, interface states, IP addresses, static routes, source device, and destination address through the `runTopology` action.

The bridge writes a temporary scenario file, starts the compiled Backbone NetOps ns-3 target, and returns the simulation output.

The older `runRoutedLab` action remains available as a small standalone compatibility test:

```json
{"action":"runRoutedLab","configure_routes":true}
```

## Engine Resolution

The bridge searches common ns-3.47 build paths for the `backbone-engine` executable. Build or rebuild only this target with:

```bash
cd /path/to/ns-3
./ns3 build backbone-engine
```
