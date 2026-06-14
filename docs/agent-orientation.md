# SkillSync Agent Orientation

> Last updated: 2026-06-14
> Audience: agents entering this repo for implementation, debugging, or review work

## 1. What this repo is

SkillSync is a macOS native app for centralized AI agent skill management.

The product model is:

- keep the canonical skill source in `~/.agent/skills`
- scan and index those skill directories
- expose them in a SwiftUI desktop app
- distribute them to agent-specific locations through symlinks
- optionally sync the source repo through Git

This is not primarily a website repo. The `website/` folder is ancillary. The product core is the macOS app plus the Rust core library.

## 2. Architecture in one pass

```text
SwiftUI Views
  -> AppState
    -> CoreBridge
      -> C FFI (asm_* functions)
        -> Rust CoreHandle
          -> AgentRegistry
          -> Scanner
          -> SymlinkManager
          -> Database
          -> GitEngine
          -> SkillWatcher
```

The practical split is:

- Swift handles UI composition, view state, and user-triggered workflows.
- Rust owns scanning, symlink behavior, persistence, git operations, and watcher lifecycle.
- The boundary is JSON over C FFI. Swift does not directly model Rust internals beyond Codable payloads.

## 3. Where to start reading

### App entry

- `macos/SkillSync/App/SkillSyncApp.swift`

What happens at launch:

- creates the main window and settings scene
- loads initial app state
- checks whether skill organization prompt should appear
- starts the file watcher

### UI state hub

- `macos/SkillSync/Models/AppState.swift`

This is the main orchestration layer on the Swift side. If a user action changes visible state, starts sync, enables/disables a skill, organizes a skill, or restores one, start here first.

Key responsibilities:

- load initial agents, skills, git status, and pending changes
- show the new-skill sheet and organize prompts
- toggle skill links for a specific agent
- drive organize/restore flows
- apply saved git auth and launch async pull/push

### Swift/Rust bridge

- `macos/SkillSync/Bridge/CoreBridge.swift`

This is the only real entry point from Swift into Rust.

Important details:

- singleton bridge
- serial `DispatchQueue` for all core access
- every `asm_*` call returns JSON or primitive success flags
- async push/pull still execute on the bridge queue, then resume back to Swift

If a Swift feature needs new backend behavior, it usually means:

1. add or extend an `asm_*` function in Rust
2. wrap it in `CoreBridge`
3. call it from `AppState`
4. bind it into a view

## 4. Core Rust modules

### `skills-core/src/ffi.rs`

Defines `CoreHandle` and the C ABI surface.

`CoreHandle` owns the long-lived subsystems:

- `registry`
- `scanner`
- `symlink`
- `db`
- `git`
- `git_auth`
- `watcher`
- `known_skill_ids`

If behavior crosses multiple Rust modules, the composition point is often in `ffi.rs`.

### `skills-core/src/scanner.rs`

Owns skill discovery and parsing.

Current behavior:

- scans one level under the source root
- only requires `SKILL.md` for a directory to count as a valid skill
- treats `manifest.json` as optional
- generates a default manifest if missing
- can detect newly added skills by comparing IDs against `known_skill_ids`

This module is the source of truth for "what counts as a skill".

### `skills-core/src/symlink.rs`

Owns skill distribution and organization.

Three link strategies are implemented:

- `Directory`: symlink the whole skill directory into the agent location
- `SingleFile`: merge `SKILL.md` content into a single output file
- `Overlay`: symlink individual files into an agent subdirectory

This module also owns:

- removing links
- organizing a skill from an agent directory into the shared source root
- organizing all skills across agents
- restoring an organized skill back to its original agent directory

If the bug is about files ending up in the wrong place, incorrect overwrite behavior, backup behavior, or restore semantics, inspect this file first.

### `skills-core/src/git_engine.rs`

Owns repository status and sync behavior.

Capabilities include:

- open or initialize a repo
- inspect status and pending changes
- set/update `origin`
- check remote connectivity using PAT auth
- auto-commit pending changes before sync
- pull with fetch + rebase
- push current branch

This repo uses libgit2 behavior, not shelling out to `git` for app runtime behavior.

### `skills-core/src/agent_registry.rs`

Owns built-in agent definitions plus custom agent CRUD and path expansion behavior.

If work touches agent visibility, custom paths, link strategy defaults, or persistence of custom agents, inspect this module along with Swift settings/agent views.

### `skills-core/src/storage/`

Owns SQLite persistence. Use this area when debugging indexed or organized skill state that should survive restarts.

### `skills-core/src/watcher.rs`

Owns file watching and event flow from the source skill directory. Use this when the app fails to notice added/changed/removed skills.

## 5. Main user-facing workflows

### Launch and initial refresh

1. `SkillSyncApp` starts
2. `AppDelegate` calls `AppState.loadInitialData()`
3. `AppState` asks `CoreBridge` for:
   - agents
   - refreshed skill DB
   - organized skill list
   - git status
   - pending changes
   - git connectivity
   - newly detected skills
4. watcher starts

### Enable or disable a skill for an agent

1. UI action in `SkillsListView`
2. `AppState.toggleSkillLink(...)`
3. `CoreBridge.createSymlink(...)` or `removeSymlink(...)`
4. Rust `SymlinkManager` performs filesystem change
5. Swift refreshes agents and organized skill list

### Organize imported skills

1. App determines whether organization has already happened
2. User accepts organize flow
3. `AppState.organizeAll()` or `organizeSkill(...)`
4. Rust moves real directories into `~/.agent/skills`
5. Original agent location is replaced with a symlink

### Git push/pull

1. Swift reads token/provider/repo URL from `UserDefaults`
2. `AppState` sends auth config into `CoreBridge`
3. Rust `GitEngine` performs connectivity check, pull, or stage-and-push
4. Result comes back as `GitStatusInfo`

## 6. UI map

The app uses `NavigationSplitView` with these tabs in `ContentView.swift`:

- `Skills`
- `Agents`
- `Sync`
- `Settings`
- `About`

Useful mental model:

- `Skills` is where most product behavior surfaces
- `Agents` is registry/configuration oriented
- `Sync` is git-oriented and exposes pending file changes
- `Settings` is for source root and visibility preferences
- `About` is release/version metadata

The detail panel is most relevant for selected skills and sync pending changes.

## 7. Build and validation rules

Project rule from `CLAUDE.md`:

- after code changes, produce a testable `.app`

Expected workflow:

- Rust changes:
  - `rtk cargo build --target aarch64-apple-darwin` in `skills-core/`
  - `rtk cargo test` in `skills-core/`
- Swift changes or mixed changes:
  - `rtk xcodebuild -project SkillSync.xcodeproj -scheme SkillSync -configuration Debug -derivedDataPath DerivedData build`

Output app:

- `DerivedData/Build/Products/Debug/SkillSync.app`

For documentation-only changes, no build is required.

## 8. Repo-specific operating rules

- Use `rtk` to prefix shell commands in this repo.
- Prefer `cymbal` for code navigation and symbol investigation.
- Edit `CLAUDE.md`, not `AGENTS.md`; `AGENTS.md` should remain a symlink mirror.
- If you change repo conventions, update the docs first.

## 9. Practical change-routing guide

When a task arrives, start here:

- UI layout, sheet behavior, tab behavior, loading state:
  - `macos/SkillSync/Views/`
  - `macos/SkillSync/Models/AppState.swift`
- New backend capability or changed app workflow:
  - `macos/SkillSync/Bridge/CoreBridge.swift`
  - `skills-core/src/ffi.rs`
- Skill recognition/parsing bugs:
  - `skills-core/src/scanner.rs`
- Linking, organizing, restore, filesystem behavior:
  - `skills-core/src/symlink.rs`
- Agent definitions or custom agent persistence:
  - `skills-core/src/agent_registry.rs`
- Sync/Git behavior:
  - `skills-core/src/git_engine.rs`
- Missed file updates / watcher bugs:
  - `skills-core/src/watcher.rs`
- Persistent state / indexed records:
  - `skills-core/src/storage/`

## 10. Current project framing

A good default assumption for this repo:

- the macOS app is the product
- the Rust core is the behavioral source of truth
- Swift should stay thin and orchestration-oriented
- filesystem and git semantics should be fixed in Rust unless the issue is purely presentation

If you need only one starting point for most non-trivial tasks, start with `AppState.swift` and the matching Rust module behind the action.
