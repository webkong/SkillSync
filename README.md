<div align="center">

# SkillSync

### One skill library for every AI coding agent

A **native macOS app** built with SwiftUI + Rust for organizing, syncing, and sharing AI coding agent skills. SkillSync keeps a canonical source in `~/.agent/skills`, then distributes the same skills to Claude Code, Codex, Cursor, Kiro, Windsurf, Copilot, Zed, and more through symlinks.

[![Release](https://img.shields.io/github/v/release/webkong/SkillSync?color=7C3AED&label=Release)](https://github.com/webkong/SkillSync/releases/latest)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B-lightgrey?logo=apple&logoColor=white)](https://github.com/webkong/SkillSync/releases)
[![Built with SwiftUI + Rust](https://img.shields.io/badge/Built%20with-SwiftUI%20%2B%20Rust-7C3AED)](#build-from-source)
[![GitHub stars](https://img.shields.io/github/stars/webkong/SkillSync?style=social)](https://github.com/webkong/SkillSync/stargazers)

<br/>

<img src="https://raw.githubusercontent.com/webkong/SkillSync/main/website/public/screenshot/s1.png" alt="SkillSync skills dashboard" width="860" />

<br/>

**If SkillSync makes your AI coding workflow easier, please star the repository so other developers can find it.**

</div>

---

## Quick Start

**Requirements:** macOS 14 Sonoma or later.

1. Download the latest build from [GitHub Releases](https://github.com/webkong/SkillSync/releases).
2. Move **SkillSync.app** to `/Applications`.
3. Launch the app and set your shared skill source root. The default is `~/.agent/skills`.
4. Open the **Skills** tab to scan your library.
5. Enable skills for the agents that should receive them.

If macOS blocks the first launch because the app is not notarized, open **System Settings -> Privacy & Security**, then choose **Open Anyway**. You only need to do this once.

---

## Features

- **Central skill library** - keep reusable agent skills in one canonical folder instead of copying them across tools.
- **25 built-in agents** - Claude Code, Codex, Cursor, Kiro, GitHub Copilot, Gemini, Zed, Windsurf, OpenCode, and more.
- **Three link strategies** - directory symlink, single merged file, or overlay links for tools with different loading models.
- **Skill organization** - move real skill files into the shared source root while leaving symlinks at the original agent location.
- **Git sync** - push and pull the shared skill library with GitHub, GitLab, or self-hosted remotes using PAT authentication.
- **File watching** - detect added, changed, and removed skills without restarting the app.
- **Custom agents** - add your own agent path and choose the link strategy that matches its skill loader.
- **Local-first design** - skill files, agent config, and the SQLite index stay on your Mac.

---

## Screenshots

<table>
<tr>
<td width="50%">

**Skills** - search, organize, delete, and distribute skills across agents.

<img src="https://raw.githubusercontent.com/webkong/SkillSync/main/website/public/screenshot/s1.png" alt="SkillSync skills list" />

</td>
<td width="50%">

**Agents** - manage built-in and custom agent destinations.

<img src="https://raw.githubusercontent.com/webkong/SkillSync/main/website/public/screenshot/s2.png" alt="SkillSync agents" />

</td>
</tr>
<tr>
<td width="50%">

**Sync** - connect a Git remote and keep your skill library portable.

<img src="https://raw.githubusercontent.com/webkong/SkillSync/main/website/public/screenshot/s3.png" alt="SkillSync git sync" />

</td>
<td width="50%">

**Settings** - tune source roots, visible agents, and local behavior.

<img src="https://raw.githubusercontent.com/webkong/SkillSync/main/website/public/screenshot/s4.png" alt="SkillSync settings" />

</td>
</tr>
</table>

---

## Supported Agents

| Agent | Default Skill Path | Link Strategy |
|-------|--------------------|---------------|
| Claude Code | `~/.claude/skills` | Directory |
| Codex | `~/.codex/skills` | Directory |
| Cursor | `~/.cursor/skills` | Directory |
| Kiro | `~/.kiro/skills` | Directory |
| GitHub Copilot | `~/.github/skills` | Directory |
| Kimi | `~/.kimi/skills` | Directory |
| Antigravity | `~/.antigravity/skills` | Directory |
| Zed | `~/.zed/skills` | Directory |
| Trae | `~/.trae/skills` | Directory |
| Windsurf | `~/.windsurf/skills` | Directory |
| Qoder | `~/.qoder/skills` | Directory |
| CodeBuddy | `~/.codebuddy/skills` | Directory |
| WorkBuddy | `~/.workbuddy/skills` | Directory |
| Gemini | `~/.gemini/skills` | Directory |
| OpenCode | `~/.opencode/skills` | Directory |
| OpenClaw | `~/.openclaw/skills` | Directory |
| Hermes | `~/.hermes/skills` | Directory |
| Grok | `~/.grok/skills` | Directory |
| RooCode | `~/.roocode/skills` | Directory |
| KiloCode | `~/.kilocode/skills` | Directory |
| Kilo CLI | `~/.kilocli/skills` | Directory |
| Goose | `~/.goose/skills` | Directory |
| OhMyPi | `~/.ohmypi/skills` | Directory |
| Pi | `~/.pi/skills` | Directory |
| Craft Agent | `~/.craft-agent/skills` | Directory |

Custom agents can use any local path and any supported link strategy.

---

## Link Strategies

| Strategy | Use When | Behavior |
|----------|----------|----------|
| Directory | The agent can load a folder of skills | Symlinks the whole skill directory into the agent skill path |
| SingleFile | The agent expects one prompt or instruction file | Merges skill content into a single generated file |
| Overlay | The agent expects individual files under a target folder | Creates symlinks for each file inside the skill directory |

---

## How It Works

```text
SwiftUI Views -> AppState -> CoreBridge
    -> C FFI JSON calls -> Rust Core
        -> Agent Registry
        -> Skill Scanner
        -> Symlink Manager
        -> Git Engine
        -> File Watcher
        -> SQLite Storage
```

- **SwiftUI app** (`macos/SkillSync`) owns the desktop UI, user actions, and app lifecycle.
- **Rust core** (`skills-core`) owns scanning, symlinks, persistence, Git operations, and file watching.
- **FFI bridge** sends JSON payloads across a serialized C ABI boundary.
- **Local data** lives under `~/.agent/`, including `agents.json` and `skills.db`.

---

## Privacy

| Protection | Detail |
|------------|--------|
| Local skill storage | Skill files stay in the local source root you choose. |
| Local index | SkillSync stores metadata in `~/.agent/skills.db`. |
| No telemetry | The app does not send analytics or usage events. |
| Explicit network actions | Network access is limited to update checks and Git sync actions you configure. |

---

## Build from Source

**Requirements:** macOS 14+, Xcode 16+, Rust, and the `aarch64-apple-darwin` target.

```bash
git clone https://github.com/webkong/SkillSync.git
cd SkillSync

# Build Rust core
cd skills-core
cargo build --target aarch64-apple-darwin
cargo test

# Build macOS app
cd ..
xcodebuild -project SkillSync.xcodeproj -scheme SkillSync -configuration Debug \
  -derivedDataPath DerivedData build

open DerivedData/Build/Products/Debug/SkillSync.app
```

Release packaging:

```bash
source scripts/version.env
scripts/release.sh build-all
```

Release artifacts are written to `dist/release/`.

---

## Troubleshooting

<details>
<summary><b>The app opens but no skills appear</b></summary>

Check that your source root contains directories with a `SKILL.md` file. SkillSync treats each first-level directory with `SKILL.md` as one skill.

</details>

<details>
<summary><b>An agent does not receive a skill</b></summary>

Verify the agent path in **Agents** or **Settings**, then confirm the selected link strategy matches the way that tool loads skills.

</details>

<details>
<summary><b>Git sync fails</b></summary>

Confirm that the remote URL is reachable and that the configured personal access token has permission to read and write the repository.

</details>

---

## Project Layout

```text
SkillSync/
|-- macos/SkillSync/        # SwiftUI macOS app
|-- skills-core/            # Rust core library compiled as staticlib
|-- scripts/                # Build, version, and signing automation
|-- docs/                   # Design notes, plans, and release docs
`-- website/                # Product website and public screenshots
```

---

## Roadmap

- Signed and notarized public releases.
- More verified agent path presets.
- Richer conflict handling for organize and restore workflows.
- Import/export flows for sharing curated skill sets.

---

## Links

- Website: <https://skillsync.webkong.top>
- Releases: <https://github.com/webkong/SkillSync/releases>
- Issues: <https://github.com/webkong/SkillSync/issues>
