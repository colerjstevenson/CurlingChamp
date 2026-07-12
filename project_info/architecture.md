# CurlingChamp Architecture Reference

This file is for future AI agents and contributors who need a code-grounded map of the project. It focuses on what currently controls behavior, where state lives, how scenes are connected, and which systems are incomplete or only represented by UI.

## Project Shape

CurlingChamp is a Godot 4.4 project with a single autoload that owns nearly all persistent game state. The project is structured around menu scenes, a playable curling match scene, and a training minigame.

Most architecture decisions are simple and centralized:

- one global singleton for persistent state: `scripts/game_manager.gd`
- scene changes through `get_tree().change_scene_to_packed()` or `change_scene_to_file()`
- JSON save/load through `scripts/save_file.gd`
- data objects stored as lightweight `RefCounted` instances via `Stone`
- UI scenes reading from the singleton on load and on `state_changed`

## Engine and Runtime Facts

- Engine target: Godot 4.4
- Renderer: GL Compatibility
- Main scene: `res://scenes/menus/startMenu.tscn`
- Autoload: `game_manager` -> `res://scripts/game_manager.gd`
- Base viewport: `720 x 1280`
- Stretch mode: `canvas_items`
- Aspect strategy: `keep_width`

## Top-Level Flow

The implemented runtime path is:

1. `scenes/menus/startMenu.tscn`
2. `scripts/start_menu.gd`
3. load save or create new save through `game_manager`
4. `scenes/Main.tscn`
5. `scripts/main_menu.gd`
6. branch into collection, auction, calendar, training, or match scenes
7. return to main hub after closing a menu or finishing a match/training session

### Scene routing currently used

- Start menu -> main hub
- Main hub -> `scenes/CurlingGame.tscn`
- Main hub -> `scenes/menus/collection.tscn`
- Main hub -> `scenes/menus/auctionMenu.tscn`
- Main hub -> `scenes/menus/CalenderMenu.tscn`
- Main hub -> `scenes/menus/trainer.tscn`
- Training game -> trainer menu
- Match -> main hub

Back navigation from several menu scenes is implemented by `scripts/backButton.gd`, which hard-codes a return to `res://scenes/main.tscn`.

## Important Naming and Platform Note

The main hub scene file on disk is `scenes/Main.tscn`, but some scripts navigate to `res://scenes/main.tscn`. This works on Windows because paths are case-insensitive there, but it is a portability risk for case-sensitive platforms and should be kept in mind during future changes.

## Architectural Center: game_manager.gd

`scripts/game_manager.gd` is the controlling abstraction for persistent gameplay state.

It owns:

- player identity
- player and opponent stone colors
- current year and week
- money
- player roster of stones
- store inventory stones
- generated schedule
- generated league player list
- human season record
- human all-time record
- majors won list
- trainer usage lock for the current week
- current save slot

It also owns the lifecycle for:

- new game initialization
- loading from save slots
- autosaving on state changes
- schedule generation
- league player generation
- store inventory generation
- weekly match completion bookkeeping

### Signal contract

`game_manager` exposes one important signal:

- `state_changed`

This signal is the main UI refresh trigger and also the autosave trigger. The singleton connects the signal to an internal autosave handler in `_ready()`.

### Autosave behavior

Any method that mutates important state usually emits `state_changed`, which triggers `_save_progress()` unless `_suspend_autosave` is set.

This means many UI-driven mutations save immediately, including:

- week and year changes
- money changes
- trainer lock updates
- match result recording
- schedule edits
- generated content refreshes

## Persistence Layer

Persistence is isolated in `scripts/save_file.gd`.

### Save characteristics

- JSON format
- 3 save slots
- slot path pattern: `user://saves/player_data_slot_%d.json`
- legacy support for older single-save file: `user://saves/player_data.json`
- save version field currently set to `1`

### Saved data

The save file stores:

- player name and colors
- week and year
- money
- player stones
- store stones
- schedule
- league players
- season and all-time records
- major wins
- trainer lock week
- saved timestamp

### Serialization rule to remember

`Stone` instances are not written directly. `SaveFile` serializes them into dictionaries and reconstructs them on load.

If future work adds fields to `Stone`, the serializer and deserializer in `save_file.gd` must both be updated.

## Data Model

### Stone

The core domain object is `Stone` from `scripts/stone_data.gd`.

It is a `RefCounted` data object, not a scene node.

Fields:

- `name`
- `age`
- `wins`
- `variant`
- `power`
- `spin`
- `precision`
- `condition`
- `power_potential`
- `spin_potential`
- `precision_potential`

Behavior:

- values are clamped to valid ranges
- stat setters respect potential caps
- `add_win()` only increments the data field; there is no automatic integration with match results yet

### Schedule entries

Schedule items are plain dictionaries with keys such as:

- `week`
- `is_major`
- `opponent`
- `venue`
- `rink_name`
- `result`
- `event_name`
- `rounds`

### League players

League players are plain dictionaries with:

- `name`
- `record`
- `skill`

There is no dedicated class for league opponents yet.

## Match Subsystem

The main playable sports loop lives in `scripts/curlinggame.gd` and `scripts/stone.gd`.

### curlinggame.gd responsibilities

- load current week settings from `game_manager`
- set human and AI display names
- set AI difficulty from scheduled opponent skill
- spawn stones in alternating order
- orchestrate human throw phases (target marker -> lock target -> shot setup -> spin -> release -> sweep -> resolve)
- handle target marker UI, `Lock Target` gating, stage prompts, and camera transitions between house and throw setup
- manage ends and per-end throw counts
- wait for all stones to settle before progressing
- prune stones that left legal play
- calculate end score
- update the in-match scoreboard UI
- end the match and notify `game_manager`

### stone.gd responsibilities

- human phase-gated throw input state machine
- target marker capture/confirmation integration and in-aim guide line rendering
- power calculation from drag length (after marker lock)
- spin selection flow via `scenes/controls/spin_setter.tscn`
- actual shot launch
- continuous curl force while moving
- sweep influence input and bounded in-flight sweep effects (forward/lateral with decay and per-throw cap)
- sprite spin visuals
- stop detection
- out-of-play detection

### AI subsystem

AI is encapsulated in `scripts/ai_player.gd`.

It is not a node; it is instantiated as a `RefCounted`-style helper from the match scene.

It performs:

- board analysis from simple stone snapshots
- shot type selection
- difficulty scaling
- target and power generation for draw, takeout, guard, and draw-second logic

The AI reads only runtime board data passed in by the match scene. It does not access the singleton directly.

## Training Subsystem

Training is split across 2 scenes:

- `scripts/trainer_menu.gd`
- `scripts/training_game.gd`

### trainer_menu.gd responsibilities

- load player stones from `game_manager`
- let the user choose a target stat and a stone
- prevent starting training when the weekly lock is active
- pass selection data to the singleton via metadata keys

### training_game.gd responsibilities

- read chosen stat and stone index back from singleton metadata
- spawn training layouts based on training type
- run 5-shot scoring logic
- convert total score into a permanent stat boost
- apply that boost directly to the selected `Stone`
- mark training as used for the current week
- return to trainer scene

### Metadata contract used between scenes

The trainer flow uses ad hoc metadata on `game_manager`:

- `trainer_selected_stat`
- `trainer_selected_rock_index`
- `trainer_selected_rock_name`

This is a lightweight scene handoff mechanism. Future agents should preserve or replace it consistently rather than partly duplicating it elsewhere.

## UI and Menu Subsystems

### start_menu.gd

Controls the 3-slot save UI.

Responsibilities:

- slot summaries via `SaveFile.get_slot_summary()`
- load slot
- delete slot
- new game setup with name and color selection

### main_menu.gd

Acts as the central hub scene controller.

Responsibilities:

- route to the main feature scenes
- refresh date and money from `game_manager`
- spawn decorative menu stones in the background

### collection_menu.gd

Read-only roster presentation of player stones using the reusable rock card control.

### auction_menu.gd

Builds buy and sell tabs from store stones and player stones.

Important: this script is presentation-only right now. It does not perform transactions.

### calendar_menu.gd

Reads schedule, league players, and records from `game_manager` and presents:

- schedule tab
- standings tab
- stats tab

### rock_window.gd

Reusable stone card view used by collection and auction flows.

Responsibilities:

- show stone name, age, wins, sprite variant, and stat bars
- infer displayed stone color from `game_manager.player_color`

Important limitation: it assumes card visuals should use the player's selected stone color rather than a per-stone color field, because the data model does not store color per stone.

## Scene Communication Patterns

The project uses a small set of repeated communication styles:

### 1. Global singleton lookup

Most gameplay and UI scripts fetch the manager via:

- `get_node_or_null("/root/game_manager")`

This is the dominant state access pattern.

### 2. Signal-driven refresh

Persistent UI refreshes usually subscribe to `game_manager.state_changed` and redraw from global state.

### 3. Direct scene changes

Scenes do not use a navigation service. They switch scenes directly with `change_scene_to_packed()` or `change_scene_to_file()`.

### 4. Metadata handoff

The training flow passes transient state using `set_meta()` and `get_meta()` on the singleton.

## Content Generation and Lists

`game_manager.gd` seeds several text lists from `res://lists` into `user://lists` on first run:

- rock names
- first names
- last names
- rink names

Generated content depends on those lists:

- player and store stone names
- league player full names
- rink assignments

This means the project allows user-side customization of generated names after the initial seed.

## Incomplete, Placeholder, or Misleading Surfaces

Several assets and scenes imply systems that are not fully live.

### Breeding

- `scenes/menus/breeder.tscn` exists
- it has a complex UI layout
- it does not currently have an active gameplay script driving a breeding system
- it still contains old stat labels like `Stamina` and `Acceleration`

Treat it as a placeholder scene, not an implemented feature.

### Auction economy

- store inventory exists in state
- buy and sell lists render correctly
- no transaction logic exists yet
- money is not spent or earned through that menu yet

### Stone stats vs match physics

- `Stone` data tracks `power`, `spin`, `precision`, and `condition`
- `stone.gd` physics currently does not consume those values
- match performance is therefore not yet stat-driven

### Majors and season structure

- schedule entries support major events
- records support majors won
- default schedule generation creates regular weekly matches only
- no bracket, playoff, or multi-round tournament flow is currently implemented

## Important Files To Read First

For most future tasks, start from these files:

- `scripts/game_manager.gd`: global state and progression
- `scripts/save_file.gd`: persistence
- `scripts/curlinggame.gd`: match controller
- `scripts/stone.gd`: shot interaction and movement
- `scripts/ai_player.gd`: AI shot selection
- `scripts/training_game.gd`: stat progression minigame
- `scripts/trainer_menu.gd`: training selection flow
- `scripts/calendar_menu.gd`: schedule and standings presentation
- `scripts/auction_menu.gd`: current store/player inventory presentation
- `scripts/stone_data.gd`: canonical stone data model

## Safe Assumptions For Future Agents

When modifying or extending the project, the safest assumptions are:

- `game_manager` is the source of truth for persistent state
- emitting `state_changed` usually means "save and refresh UI"
- scene transitions are explicit and local, not centrally orchestrated
- stone stats are meta-level progression data unless you deliberately wire them into runtime physics
- visible UI does not guarantee a full system exists behind it

## High-Risk Change Areas

Future agents should be careful when changing:

- `Stone` fields without updating save serialization
- scene file names or paths because of mixed path casing in scripts
- `state_changed` emissions because they affect autosave and UI refresh
- training metadata keys because two scenes depend on the same strings
- schedule dictionary shape because several menus and progression methods assume those keys exist

## Practical Summary

The project is currently best understood as:

- a centralized Godot management game architecture
- a fully playable curling match subsystem
- a functional training progression subsystem
- a persistent roster and schedule model
- several management features that are scaffolded in UI but not fully implemented yet

That distinction matters. Future work should branch from the actual controlling scripts, not from placeholder scenes or the broader design pitch.
