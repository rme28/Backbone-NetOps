# Changelog

All notable changes to this project are documented here.

Format inspired by [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions follow [SemVer](https://semver.org/) with a pre-release channel
(`-alpha`, `-beta`, `-rc`) until the project reaches `1.0.0`.

## [Unreleased]

### Added
- **Objectives and scoring system**: a declarative catalog of objectives
  (`game/scripts/missions/objectives.gd`), evaluated reactively against the
  game's event journal. Score and completed objectives are part of the save.
  An in-game panel shows the score and the objective checklist live.
- **Equipment palette**: press Tab to pick what to place (router, switch, PC),
  driven by a data file (`game/resources/equipment/devices.json`) so new
  hardware can be added without touching game logic.
- **Mouse-based cabling**: aim at a device and left-click, aim at a second one
  and left-click again to connect them. The game auto-picks the first free
  interface on each side (`game/scripts/network/interfaces.gd`) and draws a
  simple cable between the two devices. Links are journaled and replayed like
  device placement.
- **`getDeviceCatalog` bridge action**: returns Packet Tracer's full live device
  catalog (151 models across 39 categories), read directly from PT's internal
  `deviceTypes`/`allDeviceTypes` objects. Not wired into the game palette yet
  (still using the static JSON) - groundwork for a richer, auto-updating
  equipment palette.
- **Discovered real interactive CLI access** via `getCommandLine()` on a PT
  device object (`enterCommand`, `getOutput`, `getPrompt`): full read/write
  access to the actual device terminal, including parseable `ping` results
  (`Success rate is X percent`). See `bridge/README.md`.
- **In-game device console**: aim at a device and press `T` to open a real
  terminal wired to its actual Packet Tracer CLI (`cliSend`/`cliRead` bridge
  actions). Commands typed in-game are genuinely executed by PT - no fake
  terminal, real IOS output, real errors, real `ping` results.

### Fixed
- **Console commands now persist across save/load**: every command typed in
  the in-game terminal is journaled (`cli_command` events) and replayed on
  load, with a boot delay before a device's first command so `no`/`enable`
  aren't sent before the device is ready. Previously, devices and links
  survived a reload but their configuration didn't.
- The console input field could lose keyboard focus (most noticeably on Tab,
  which triggered Godot's default UI focus navigation instead of typing a
  character) - focus is now pinned to the input field.
- Pressing Enter with an empty line now sends an actual blank command (needed
  to page through `--More--` output, e.g. `show running-config`), instead of
  being silently ignored.
- **Growing console latency**: the auto-refresh timer queued a new read every
  0.5s even if the previous one hadn't returned, and PT only serves one job
  per poll (~500ms) - the backlog grew unbounded and output appeared later
  and later. Fixed with an in-flight guard that skips a tick if a request is
  still pending.

### Investigated
- Whether the game could save/load the *real* `.pkt` file (via
  `fileSaveToBytes`/`fileOpenFromBytes`) instead of replaying the event
  journal. Technically callable, but converting a 45KB result to base64 took
  23 real seconds in PT's sandboxed engine - not usable. See `bridge/README.md`.
  Sticking with event-sourcing for saves.

### Changed
- **Project restructuring** for scalability: `game/` is now organized into
  `scenes/` (world, player, ui), `scripts/` (core, network, player, world, ui,
  missions), and `resources/`. `bridge/` is split into `server.py` (Flask/HTTP),
  `commands.py` (action translation), and `packettracer.py` (low-level PTBuilder
  protocol/escaping). Adding a new command or a new equipment type should now
  only touch one or two files instead of a single monolithic script.

## [0.2.0-alpha] - 2026-07-19

Complete save system and quality-of-life pass: the game mostly runs itself
(bridge auto-launch), and a run can be saved, quit, and reloaded with Packet
Tracer reflecting exactly the loaded state.

### Added
- **Bridge auto-launch**: the game detects the bridge on startup and launches
  it automatically if missing, with a status message shown in-game (connected / error).
- **Main menu**: new game, load a save, delete a save.
- **Save system via event replay** (event sourcing): every action is logged;
  saving writes the journal, loading replays it into an empty PT instance.
  The game is the single source of truth (does not rely on any PT-native save).
- **Pause menu** (Esc): resume, save, return to main menu.
- **Automatic PT reset**: starting a new game or loading a save now clears the
  Packet Tracer canvas first, via `ipc.appWindow().fileNew(false)` (found by
  exploring PT's internal API). PT now always reflects the current save exactly.

## [0.1.0-alpha] - 2026-07-19

First playable vertical slice: walk through a 3D room, place equipment, see it
appear in the real Cisco Packet Tracer engine.

### Added
- **Python bridge** (`bridge/server.py`): HTTP mailbox server between the game
  and PTBuilder (`POST /command`, `GET /next`, `POST /result`,
  `GET /result/<id>`, `GET /health`).
- Translation of high-level commands (`addDevice`, `addLink`, `configureIos`,
  `configurePcIp`, `getDevices`, `raw`) into PTBuilder JS + outbound XHR wrapping.
- Job queue with `delay_before` to space out device creation and configuration
  (device boot time).
- **Godot 4.7 game** (`game/`): 3D FPS room built in code, WASD + mouse movement,
  `Bridge` autoload (HTTP client), `E` key to place a router (cube in-game and
  a real device in Packet Tracer).

### Fixed / discovered
- **CORS is required for Packet Tracer 9.x**: without
  `Access-Control-Allow-Origin` headers on the bridge, the PT webview blocks
  reading `GET /next` responses and polling fails silently. Fixed with an
  `@app.after_request` hook (see `bridge/README.md`).

### Validated in the field
- PT 9.0.0: `addDevice`, `addLink` (link UP), `configureIosDevice` (hostname,
  IP, and `no shutdown` applied), `getDevices`.
- Full chain from the game: routers placed in 3D appear in PT.

[Unreleased]: https://github.com/rme28/Backbone-NetOps/compare/v0.2.0-alpha...HEAD
[0.2.0-alpha]: https://github.com/rme28/Backbone-NetOps/compare/v0.1.0-alpha...v0.2.0-alpha
[0.1.0-alpha]: https://github.com/rme28/Backbone-NetOps/releases/tag/v0.1.0-alpha
