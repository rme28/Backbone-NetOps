# Python bridge - Godot game <-> Packet Tracer (PTBuilder)

HTTP mailbox on `127.0.0.1:8081`, split into three files:

- `server.py` - Flask app, HTTP routes, job queue/results state.
- `commands.py` - translates high-level actions (JSON from the game) into PTBuilder JS calls.
- `packettracer.py` - low-level protocol layer: JS string escaping, sandbox-escape wrapping.

## Running the bridge

```bash
cd bridge
pip install -r requirements.txt
python server.py
```

## Endpoints

- `POST /command` - the game submits a high-level command, gets back `{"job_id": "..."}`.
- `GET /result/<job_id>` - the game reads the result: `{"status":"pending"}` /
  `{"status":"ok","result":...}` / `{"status":"error","error":"..."}`.
- `GET /health` - liveness probe for the game (does not consume the job queue, unlike `/next`).
- `GET /next` - PTBuilder polls here (every 500ms) to fetch the next JS code to run.
  Empty if there's nothing to do.
- `POST /result` - PTBuilder posts back the raw result of the execution here.

## Actions supported by `POST /command`

```json
{"action":"addDevice","name":"R1","model":"2911","x":100,"y":100}
{"action":"addLink","dev1":"R1","iface1":"GigabitEthernet0/0","dev2":"R2","iface2":"GigabitEthernet0/0","cable":"straight"}
{"action":"configureIos","name":"R1","commands":["enable","configure terminal","hostname R1","exit"]}
{"action":"configurePcIp","name":"PC1","dhcp":false,"ip":"192.168.0.10","mask":"255.255.255.0","gateway":"192.168.0.1"}
{"action":"getDevices"}
{"action":"clearTopology"}
{"action":"raw","code":"result = 1+1;"}
```

Every command accepts an optional `"delay_before": <seconds>` field: the job stays
queued without being served until that delay has elapsed (useful to let a freshly
placed device finish booting before configuring it).

Adding a new action: add a case in `commands.py`, and a matching call on the game
side in `game/scripts/network/bridge_client.gd`.

## Testing standalone with curl (no PT, no game)

```bash
curl -X POST http://127.0.0.1:8081/command -H "Content-Type: application/json" \
  -d '{"action":"addDevice","name":"R1","model":"2911","x":100,"y":100}'
# -> {"job_id": "..."}

curl http://127.0.0.1:8081/next
# -> the JS code PTBuilder is supposed to run

curl -X POST http://127.0.0.1:8081/result -d '{"id":"<job_id>","ok":true,"result":true}'

curl http://127.0.0.1:8081/result/<job_id>
# -> {"status":"ok","result":true}
```

## Bootstrap to paste into PTBuilder's Builder Code Editor

Once, after enabling IPC (`Extensions > IPC > Options`, port 39000, "Allow Remote
Applications" + "Always Listen On Start"). This code runs the polling loop that
fetches commands from the bridge:

```javascript
window.webview.evaluateJavaScriptAsync("setInterval(function(){var x=new XMLHttpRequest();x.open('GET','http://127.0.0.1:8081/next',true);x.onload=function(){if(x.status===200&&x.responseText){$se('runCode',x.responseText)}};x.onerror=function(){};x.send()},500)");
```

If you restart the bridge while PT was actively polling, the loop can sometimes
stop working (connection reset mid-poll). If commands stop being picked up after
a bridge restart, just re-paste and re-run this snippet.

## Warning: CORS (Packet Tracer 9.x)

The server sends `Access-Control-Allow-Origin: *` headers on **all** responses
(`@app.after_request` in `server.py`). This is **required**: without it, the
Packet Tracer 9.x webview blocks reading `GET /next` responses and polling breaks
silently (the server replies 200, but PTBuilder can't read the code to execute).
Do not remove these headers.

## Discovered via the PT script engine's global `ipc` object

Beyond PTBuilder's own six functions (`addDevice`, `addLink`, `configureIosDevice`,
`configurePcIp`, `getDevices`, `addModule`), the global `ipc` object exposes much
more of Packet Tracer's internal API. Notably:

- `ipc.appWindow().fileNew(false)` clears the whole topology (equivalent to
  File > New, no save prompt). Used by the `clearTopology` action.
- `ipc.appWindow()` also exposes `fileOpen`, `fileSave`, `fileSaveToBytes`, etc. -
  a possible path to native `.pkt` save/load, not used yet (the game currently
  saves via event-sourcing/replay instead, see `game/scripts/core/game_state.gd`).
- `ipc.network()` exposes `getDeviceCount`, `getDevice`, `getDeviceAt`,
  `getLinkCount`, but no per-device removal - hence using `fileNew` to reset.

Also discovered outside `ipc`, two more global objects give the **full live
device catalog** straight from PT (no need to hand-maintain a model list):

- `deviceTypes`: category name -> category id (39 entries: router, switch, pc,
  server, accesspoint, printer, ipphone, etc.)
- `allDeviceTypes`: model string -> category id (151 entries, e.g.
  `"2911"` -> router, `"2960-24TT"` -> switch, `"PC-PT"` -> pc)

Exposed via the `getDeviceCatalog` action (`commands.py`), which cross-references
both objects and returns `{category: [model, ...]}`. Verified accurate for the
categories actually used in the game (router, switch, pc, server, accesspoint,
printer). **Caveat**: `deviceTypes` only maps ids 0-38, but `allDeviceTypes`
references ids beyond that range (39+) for rarer/newer categories (IoT sensors,
patch panels, wireless controllers...) - for those, the category name falls back
to the raw numeric id and the grouping can look inconsistent. Not an issue for
the models this game actually uses, but don't trust the exotic categories blindly.

Discovery method: submit a `"raw"` action with JS that enumerates
`Object.getOwnPropertyNames(ipc)` (and sub-objects) and inspect the result.

## Real interactive CLI access: `getCommandLine()`

`ipc.network().getDevice(name).getCommandLine()` returns a live command-line
object wired to the device's actual CLI - the same one shown in PT's own
"Router0"-style config window. This is a full interactive terminal, not the
one-shot/invisible `configureIosDevice`:

- `enterCommand(str)` - types a full command and presses Enter (handles
  multi-line flows like `configure terminal` / `interface ...` / `end` fine
  when called once per line).
- `getOutput()` - returns the **entire CLI transcript** so far (boot banners,
  prompts, command echoes, error messages - everything a human would see).
- `getPrompt()` - the current prompt string (e.g. `"Router#"`, or a yes/no
  question during the setup wizard).
- `enterChar(c)` - single character input, for interactive prompts.

Validated end to end on PT 9.0.0: booted a router, answered "no" to the setup
wizard, `enable`, configured an interface IP, then ran `ping <ip>` and read
back the real result via `getOutput()`:

```
Sending 5, 100-byte ICMP Echos to 192.168.50.1, timeout is 2 seconds:
.....
Success rate is 0 percent (0/5)
```

The `Success rate is X percent (Y/Z)` line is reliably parseable - this is how
the game can know whether a ping actually succeeded (for objectives/scoring),
without needing to pop or embed any Packet Tracer window. It also means an
in-game terminal can be a thin pass-through to this object instead of a fake
CLI: send what the player types via `enterCommand`, poll `getOutput()`/`getPrompt()`
for the response.

Caveat: commands take real (simulated) time to resolve - e.g. a 5-packet ping
takes several seconds before `getOutput()` reflects the final result. Poll
with a delay rather than reading immediately after sending a command.
