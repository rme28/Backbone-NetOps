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
