# Agent Skills Manager

macOS native application for unified management of AI Coding Agent skills/prompts. Centralizes skill files from `~/.agent/skills` and distributes them to multiple AI coding agents (Claude Code, Cursor, Windsurf, Copilot, Zed, etc.) via symlinks.

## Tech Stack

- **Frontend**: SwiftUI (macOS 14.0+, Swift 5.0)
- **Core Engine**: Rust (compiled as `staticlib`)
- **FFI Bridge**: C FFI with JSON serialization
- **Database**: SQLite via `rusqlite`
- **Git**: libgit2 via `git2-rs` (stage, commit, pull, push with PAT auth)
- **File Watching**: `notify-rs` (macOS kqueue)

## Project Structure

```
AgentSkillsManager/
├── macos/SkillsManager/           # SwiftUI macOS application
│   ├── App/                       # App entry point, lifecycle
│   ├── Bridge/                    # C FFI bridge (CoreBridge.swift + bridging header)
│   ├── Models/                    # AppState (ObservableObject), DataModels (Codable)
│   ├── Views/                     # All SwiftUI views
│   │   ├── SkillsPanel/           # Skill list, detail, organize prompts
│   │   ├── AgentsPanel/           # Agent list, add agent, agent icons
│   │   ├── SyncPanel/             # Git pull/push UI
│   │   ├── Settings/              # Source root, agent visibility
│   │   ├── About/                 # Version, update check, license
│   │   └── Components/            # QuickHelpModifier tooltip
│   └── Resources/                 # Info.plist, entitlements
├── skills-core/                   # Rust core library
│   └── src/
│       ├── lib.rs                 # Module declarations
│       ├── ffi.rs                 # 28 extern "C" functions (asm_*)
│       ├── models.rs              # Shared data structures
│       ├── agent_registry.rs      # 25 built-in + custom agents CRUD
│       ├── scanner.rs             # Skill directory scanning + manifest parsing
│       ├── symlink.rs             # 3 link strategies (Directory/SingleFile/Overlay)
│       ├── git_engine.rs          # Git operations
│       ├── watcher.rs             # kqueue file watcher (500ms debounce)
│       └── storage/               # SQLite database
├── scripts/
│   ├── release.sh                 # Build automation (rust → app → zip)
│   ├── self_signed_codesign.sh    # Self-signed cert generation
│   └── version.env                # VERSION=0.1.0, BUILD_NUMBER=1
└── docs/plans/                    # Design and implementation docs
```

## Architecture

```
SwiftUI (macOS) → AppState → CoreBridge (serial DispatchQueue)
    → C FFI (JSON over c_char*) → Rust Core (CoreHandle)
        ├── agent_registry.rs  → ~/.agent/agents.json
        ├── scanner.rs         → File system scanning
        ├── symlink.rs         → Symlink management
        ├── git_engine.rs      → Git operations
        ├── watcher.rs         → File system monitoring
        └── storage/db.rs      → ~/.agent/skills.db (SQLite)
```

## Key Features

- **25 built-in agents**: claude-code, cursor, windsurf, copilot, zed, etc.
- **3 symlink strategies**: Directory, SingleFile (merge into one), Overlay (individual files)
- **Skill organization**: Move real files to source root, leave symlinks at original locations
- **Git sync**: Manual push/pull with PAT authentication (GitHub/GitLab/self-hosted)
- **File watching**: Real-time detection of new/changed/removed skills
- **Custom agents**: User-defined agents with custom paths and link types

## Build & Test

```bash
# Rust (always run after any Rust change)
cd skills-core && cargo build --target aarch64-apple-darwin
cd skills-core && cargo test    # ~29 unit tests

# macOS app (always run after any code change to produce a testable .app)
# Builds Rust → Swift → produces SkillsManager.app in DerivedData/Build/Products/Debug/
xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug \
  -derivedDataPath DerivedData build

# Release packaging
source scripts/version.env
scripts/release.sh build-all

# Code signing
scripts/self_signed_codesign.sh
```

## Workflow

**每次代码修改后，必须编译出一个可测试的 .app**。顺序如下：

1. **Rust 层修改** → `cargo build --target aarch64-apple-darwin` + `cargo test`
2. **Swift 层修改**（或全部修改） → `xcodebuild ... build`
3. 产出位于 `DerivedData/Build/Products/Debug/SkillsManager.app`

如果 Rust 代码未改动，可跳过 `cargo build` 直接跑 `xcodebuild`（Xcode 构建阶段会自动编译 Rust）。

## Rust Dependencies

serde, serde_json, git2, notify (macos_kqueue), walkdir, dirs, uuid, chrono, rusqlite (bundled), tempfile (dev)

## Swift Frameworks

SwiftUI, AppKit/Foundation, Security, libskills_core.a (via `-force_load`)
