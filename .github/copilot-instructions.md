Yes. The easiest way is to give you the raw Markdown without the surrounding chat formatting. Copy everything inside the block below into:

```
.github/copilot-instructions.md
```

```markdown
# Copilot Instructions for CurlingChamp (Godot 4.x)

> These instructions define how GitHub Copilot (or any AI coding assistant) should work within the CurlingChamp Godot project.
>
> The goal is to make reliable, maintainable changes while preserving the existing architecture and avoiding unnecessary edits.

---

# AI Mission

When contributing to this project, prioritize:

1. Make the smallest correct change.
2. Preserve existing architecture and gameplay systems.
3. Reuse existing code before creating new systems.
4. Avoid unnecessary refactoring.
5. Keep changes localized.
6. Do not modify unrelated files.
7. Prefer simple solutions over complex abstractions.

The best implementation is usually the one that solves the requested problem while touching the fewest files.

---

# Before Every Task

Before making changes:

1. Read:

```

project_info/current_task.md

```

2. Review relevant documentation:

```

project_info/
├── architecture.md
├── gameplay.md
├── todo.md
└── current_task.md

```

3. Identify the smallest number of files required.

Do not begin by scanning the entire project.

---

# Project Structure

```

CurlingChamp/

├── .github/
│   └── copilot-instructions.md

├── addons/
│   └── Godot plugins

├── assets/
│   ├── Auction/
│   ├── blender/
│   ├── curling/
│   ├── icons/
│   └── UI/

├── data/
│   └── JSON templates and game data

├── docs/
│   └── Front end docs for web demo

├── Fonts/

├── lists/
│   ├── first-names.txt
│   ├── horseRaces.txt
│   ├── last-names.txt
│   ├── rink_names.txt
│   └── rockNames.txt

├── music/

├── project_info/
│   ├── architecture.md
│   ├── current_task.md
│   ├── gameplay.md
│   └── todo.md

├── scenes/
│   ├── controls/
│   ├── menus/
│   ├── CurlingGame.tscn
│   ├── Main.tscn
│   ├── MainMenu.tscn
│   ├── ScoreBoard.tscn
│   └── Stone.tscn

├── scripts/
│   ├── ai_player.gd
│   ├── auction_menu.gd
│   ├── calendar_menu.gd
│   ├── collection_menu.gd
│   ├── curlinggame.gd
│   ├── game_manager.gd
│   ├── save_file.gd
│   ├── stone.gd
│   └── training_game.gd

├── themes/

└── project.godot

```

---

# File Priority

## Primary Development Files

Most code changes should happen in:

```

scripts/
scenes/
project_info/

```

These contain:

- gameplay logic
- UI behavior
- game flow
- documentation

---

## Secondary Files

Only modify when required:

```

data/
lists/
themes/
addons/

```

---

## Asset Files

Treat these as read-only.

```

assets/
music/
Fonts/

```

Confirm with user before you inspect or modify any of these files

---

# Context Management

Context is limited.

Do not load files unless they are needed.

Before opening another file, ask:

> Does this file directly help solve the current task?

If no:

Do not open it.

---

# Preferred Context Order

For most tasks:

1. `project_info/current_task.md`
2. Relevant `.tscn` scene
3. Attached `.gd` script
4. supporting scripts if required

Avoid loading entire systems.

---

# Never Load Unless Required

Avoid inspecting:

```

.godot/
.git/
.git-local-backups/

```

Avoid opening:

```

.png
.jpg
.wav
.mp3
.ogg
.blend
.psd
.fbx
.glb

```

These files provide little value for code changes and waste context.

---

# Scene and Script Relationship

Scenes usually have a matching script.

Examples:

```

CurlingGame.tscn
-> curlinggame.gd

Stone.tscn
-> stone.gd

auctionMenu.tscn
-> auction_menu.gd

collection.tscn
-> collection_menu.gd

trainer.tscn
-> trainer_menu.gd

````

When modifying gameplay:

Prefer editing the script first.

Only edit scenes when node structure or exported properties require it.

---

# Autonomous Implementation Workflow

For every task:

## Step 1

Understand the requested change.

## Step 2

Locate existing implementations.

Search before creating new code.

## Step 3

Create a small implementation plan.

## Step 4

Make the smallest possible edit.

## Step 5

Check for:

- syntax errors
- missing references
- broken signals
- warnings

## Step 6

Stop.

Do not continue with unrelated improvements.

---

# Large Changes

If a change affects more than three files:

Before coding:

Explain:

- what files will change
- why they need changes
- the implementation approach

Then proceed.

---

# AI Guardrails

## Never Do This Unless Explicitly Requested

- Rename files
- Rename nodes
- Move folders
- Rewrite working systems
- Replace existing architecture
- Refactor unrelated code
- Change save formats
- Modify project settings
- Modify assets
- Regenerate imports
- Change scene hierarchy unnecessarily

---

# Scene Editing Rules

Godot scenes are sensitive.

When modifying `.tscn` files:

Only change:

- required nodes
- required exported variables
- required signal connections

Never:

- reorder nodes
- rename nodes
- delete existing connections
- reset exported values
- rewrite entire scenes

---

# Cross-Platform Path Safety (Web/Linux)

Web exports and Linux environments are case-sensitive.

When using scene/resource paths in `preload()`, `load()`, `change_scene_to_file()`, exports, or project settings:

- Match filename casing exactly as it appears on disk.
- Treat path case mismatches as blockers before finishing.
- Verify renamed/new paths against actual files under `scenes/` and `scripts/`.

Example portability failure to avoid:

- `res://scenes/Main.tscn` vs actual file `res://scenes/main.tscn`.

Windows may still run with mismatched casing, but web/Linux can fail at startup.

---

# Coding Standards

## Language

Use:

- Godot 4.x
- GDScript

Prefer static typing.

Example:

```gdscript
var score: int = 0
var velocity: Vector2
````

---

# Naming

| Type      | Convention       |
| --------- | ---------------- |
| Files     | snake_case       |
| Scenes    | snake_case       |
| Variables | snake_case       |
| Functions | snake_case       |
| Classes   | PascalCase       |
| Constants | UPPER_SNAKE_CASE |

---

# Code Style

Prefer:

* small functions
* clear naming
* typed variables
* early returns
* signals
* reusable components

Avoid:

* giant scripts
* duplicated logic
* magic numbers
* unnecessary inheritance
* deep nested conditions

---

# Scripts

Keep scripts focused.

A script should represent one main responsibility.

Good:

```
stone.gd
    controls stone behavior

save_file.gd
    manages saving

game_manager.gd
    manages game state
```

Avoid:

```
game_manager.gd
    handles everything
```

---

# Signals

Prefer signals over constant checking.

Example:

```gdscript
signal game_finished
```

Use signals for:

* UI updates
* state changes
* gameplay events

---

# Resources

Use:

```gdscript
preload()
```

for static resources.

Use:

```gdscript
load()
```

for dynamic resources.

Cache resources that are reused frequently.

---

# Autoloads

Keep global systems minimal.

Use autoloads for:

* save systems
* global configuration
* game state
* shared services

Avoid putting gameplay objects inside autoloads.

---

# Error Handling

Use:

```gdscript
assert()
```

for development assumptions.

Handle missing resources gracefully.

Do not silently ignore errors.

---

# Architecture Rules

Preferred dependency flow:

```
UI

↓

Menus / Controllers

↓

Game Managers

↓

Gameplay Objects

↓

Data / Resources
```

Avoid circular dependencies.

UI should not directly control low-level gameplay logic.

---

# Feature Boundaries

CurlingChamp contains multiple gameplay systems:

* Curling gameplay
* Auction
* Training
* Collection
* Calendar
* Menus

Unless requested:

Keep changes inside the current feature.

Do not refactor shared systems while implementing unrelated features.

---

# Data Rules

Treat these as data sources:

```
data/
lists/
```

Do not hardcode large datasets into scripts.

Prefer:

* JSON
* Resources
* external data files

---

# Testing

Before finishing:

Verify:

* no parser errors
* no new warnings

For important systems, add tests where practical.
Don't try and run tests in godot as they won't open correctly.

---

# Documentation

Update:

```
project_info/
```

when adding:

* new systems
* new gameplay mechanics
* new architecture patterns
* new APIs

Documentation should describe the current implementation.

---

# Definition of Done

A task is complete when:

* Requested feature works
* Only necessary files changed
* No unrelated refactors introduced
* No warnings/errors added
* Documentation updated if needed
* Code follows project conventions

After completion:

Stop.

---

# General Rule

Be a careful senior developer.

Prioritize:

* correctness
* simplicity
* maintainability
* minimal changes

Do not optimize for writing the most code.

Optimize for making the right change.
