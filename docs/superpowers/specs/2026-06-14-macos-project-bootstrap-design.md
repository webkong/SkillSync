# macOS Project Bootstrap Skill Design

> Date: 2026-06-14
> Status: draft for review
> Scope: a reusable skill plus co-located templates for bootstrapping macOS projects with build, package, and release workflows

## 1. Goal

Create a reusable skill installed under `~/.agents/skills` that can bootstrap new macOS projects with working build and release scaffolding from day one.

The system should cover two project families that already exist in the user's workspace:

- SwiftPM-first macOS app packaging, based on `ClipboardManager`
- Xcode + Rust staticlib + SwiftUI app packaging, based on `TokenViewer` and also relevant to `SkillSync`

The deliverable is not only documentation. It must become an operational skill with templates and helper scripts that can generate a fresh project skeleton, wire build/release flows, and validate the first build.

## 2. Confirmed product shape

The user approved these decisions:

- support a general macOS bootstrap system rather than a single-project clone
- support both project families, with multiple presets
- use a two-layer model:
  - templates generate the initial project skeleton
  - the skill applies project-specific substitutions, setup, and first-build validation
- store the skill in `~/.agents/skills`
- store template source inside the skill directory itself for the first iteration

This implies the first implementation should optimize for a fully local, self-contained workflow rather than cross-repo indirection.

## 3. Reference project findings

### 3.1 ClipboardManager pattern

`ClipboardManager` is a SwiftPM-first macOS app with custom shell packaging.

Observed release/build characteristics:

- `script/build_and_run.sh` creates a local `.app` bundle manually from SwiftPM build output
- it supports `native`, `arm64`, `x86_64`, and `universal` app builds
- it writes `Contents/Info.plist` directly
- it copies runtime resources into `Contents/Resources`
- it supports stable signing identities and a self-signed fallback for internal distribution
- `script/release.sh` builds release app/zip/pkg/dmg plus website publish and GitHub release upload
- `script/version.env` is the version source of truth
- `script/sync_version.sh` pushes version values into `Info.plist`

What this teaches us:

- SwiftPM app projects need app-bundle staging logic, not just `swift build`
- packaging logic should be script-owned and reproducible without Xcode UI
- universal-arch handling and signing policy should be first-class template concerns

### 3.2 TokenViewer pattern

`TokenViewer` is an Xcode + Rust staticlib project with release scripting around both the Rust core and the macOS app.

Observed release/build characteristics:

- `run.sh` conditionally skips Rust rebuild if sources are unchanged
- `build-rust.sh` detects architecture and handles Rust target selection
- `script/release.sh` owns Rust build, Xcode release app build, zip/pkg/dmg generation, website publish, and GitHub release upload
- `script/version.env` is the version source of truth
- release scripts enforce stable signing for packaged artifacts
- the project depends on Rust toolchain presence, Xcode availability, and sometimes explicit `DEVELOPER_DIR`

What this teaches us:

- hybrid Xcode/Rust projects need explicit toolchain preflight
- Rust build target path and Xcode link expectations must stay aligned
- release scripts should fail clearly when signing or release notes are missing

### 3.3 Shared patterns

Both projects independently converged on the same fundamentals:

- `script/version.env` as source of truth
- shell scripts as the build/release control plane
- local app packaging paths under `dist/`
- release notes under `docs/releases/vX.Y.Z.md`
- stable-signing enforcement for distributable artifacts
- website deployment as an optional extension of release, not part of core build

These commonalities are strong enough to extract into a reusable skill architecture.

## 4. Proposed output structure

The first implementation should live under:

```text
~/.agents/skills/macos-project-bootstrap/
├── SKILL.md
├── references/
│   ├── architecture.md
│   ├── preset-matrix.md
│   ├── reference-projects.md
│   └── release-patterns.md
├── templates/
│   ├── macos-swiftpm-app/
│   └── macos-xcode-rust-ffi-app/
└── scripts/
    ├── bootstrap.sh
    ├── render_template.sh
    ├── verify_env.sh
    └── first_build.sh
```

This keeps the skill installable and self-contained:

- `SKILL.md` explains when and how to invoke the bootstrap flow
- `references/` explains the design and decisions
- `templates/` contains real project template files
- `scripts/` performs rendering and validation

## 5. Preset model

The system should start with two explicit presets.

### Preset A: `macos-swiftpm-app`

Use when the new app is SwiftPM-first and does not require an Xcode project as the primary development artifact.

Template responsibilities:

- `Package.swift`
- `Sources/<AppName>/`
- `Tests/`
- `script/build_and_run.sh`
- `script/release.sh`
- `script/version.env`
- `script/version_utils.sh`
- optional `script/sync_version.sh`
- `signing/`
- `dist/`
- `docs/releases/`
- `website/` optional starter

### Preset B: `macos-xcode-rust-ffi-app`

Use when the app has:

- SwiftUI macOS frontend
- Rust core crate compiled as staticlib
- Xcode project as primary app build surface

Template responsibilities:

- `macos/<AppName>.xcodeproj`
- `macos/<AppName>/...`
- `core/` or `<rust-core>/`
- Rust `Cargo.toml` and `src/`
- bridging header and bridge wrapper
- `script/build_and_run.sh` or `run.sh`
- `script/release.sh`
- `script/version.env`
- `script/version_utils.sh`
- `signing/`
- `docs/releases/`
- optional `website/`

## 6. Skill behavior

The skill should not just explain the process. It should drive it.

Expected flow:

1. determine preset
2. collect a small parameter set
3. copy template into target directory
4. render placeholders across files
5. apply preset-specific adjustments
6. run environment verification
7. run first build
8. report artifact path and next steps

### Required input parameters

Minimum required inputs:

- project name
- display name
- bundle identifier
- preset

Optional inputs:

- Rust crate name
- minimum macOS version
- app process name
- release asset display name
- website enabled or disabled
- signing mode:
  - ad-hoc local only
  - self-signed internal
  - developer identity expected

### Required generated outputs

The generated project must include:

- build/run script
- release script
- version source file
- release notes directory
- `.gitignore`
- `CLAUDE.md`
- `AGENTS.md` symlink to `CLAUDE.md`

## 7. Template rendering model

Templates should use a minimal placeholder vocabulary rather than a general template engine.

Proposed token set:

- `__PROJECT_NAME__`
- `__DISPLAY_NAME__`
- `__BUNDLE_ID__`
- `__APP_EXECUTABLE__`
- `__MIN_MACOS_VERSION__`
- `__VERSION__`
- `__BUILD_NUMBER__`
- `__RUST_CRATE_NAME__`

Rendering should be done by a shell script so the skill remains portable and local.

The first implementation should avoid introducing Ruby, Python templating frameworks, or Node-only generators unless a preset truly requires them.

## 8. Build and release abstraction

The skill should encode a shared release model and allow preset-specific implementation underneath.

### Shared release contract

Every generated project should support a predictable set of commands:

- `script/build_and_run.sh` for local development
- `script/release.sh build-app`
- `script/release.sh build-zip`
- `script/release.sh build-pkg`
- `script/release.sh build-dmg`

Optional but supported:

- `script/release.sh build-website`
- `script/release.sh push-website`
- `script/release.sh push-release`

### Shared version contract

Every generated project should treat `script/version.env` as source of truth.

If downstream project files need synchronization, the preset may also provide:

- `script/version_utils.sh`
- `script/sync_version.sh`

### Shared signing contract

The generated release path should distinguish three cases:

- local debug build may use ad-hoc signing
- packaged internal build should prefer reusable self-signed identity
- packaged external release should require stable signing identity

This is a core abstraction because both reference projects already encode that policy.

## 9. Environment verification

The skill should check the local machine before claiming success.

### SwiftPM preset checks

- `swift`
- `swift package`
- optional `pkgbuild`
- optional `hdiutil`

### Xcode + Rust preset checks

- `cargo`
- `rustc`
- `xcodebuild`
- active `DEVELOPER_DIR` or discoverable `/Applications/Xcode.app`

The skill should emit specific remediation guidance when checks fail, for example:

- missing `cargo` in `PATH`
- `xcode-select` pointing to CommandLineTools instead of full Xcode
- missing Rust target

## 10. First-build verification

A generated project is not complete until it passes the first build.

The skill should run:

- SwiftPM preset:
  - `script/build_and_run.sh --verify` if supported
  - or equivalent build validation
- Xcode + Rust preset:
  - Rust core build
  - app build via `xcodebuild`

Success criteria:

- build succeeds
- expected `.app` or binary artifact exists
- skill prints artifact path

For the Xcode + Rust preset, the generated project must avoid the configuration mismatch currently visible in `SkillSync`, where Debug build logic and static library link path disagree.

## 11. Initial non-goals

The first version should not attempt to:

- support iOS, iPadOS, or Catalyst
- support Linux or Windows packaging flows
- generate notarization-ready production pipelines automatically
- generate CI workflows for every host
- support more than the two initial presets

These are later extensions, not v1 requirements.

## 12. Recommended implementation phases

### Phase 1: skill skeleton and references

- create skill directory under `~/.agents/skills`
- write `SKILL.md`
- write design/reference docs

### Phase 2: shared scripts

- add environment verification script
- add simple template renderer
- add bootstrap entrypoint

### Phase 3: `macos-swiftpm-app` template

- extract minimal reusable form from `ClipboardManager`
- remove project-specific business logic
- prove first-build flow

### Phase 4: `macos-xcode-rust-ffi-app` template

- extract minimal reusable form from `TokenViewer`
- add Rust/Xcode path alignment rules
- prove first-build flow

### Phase 5: acceptance testing

- generate one project from each preset
- run first build for each
- inspect produced scripts and directories

## 13. Risks and constraints

### Risk: overfitting to reference projects

Mitigation:

- extract contracts, not business-specific implementation
- keep preset logic isolated

### Risk: Xcode project templating is brittle

Mitigation:

- keep first preset simple and low-variable
- constrain placeholder edits to known stable paths and names

### Risk: signing and packaging differ per machine

Mitigation:

- make signing mode explicit
- separate local build success from distributable release readiness

### Risk: generated projects fail on clean machines

Mitigation:

- encode environment preflight and explicit remediation in the skill

## 14. Acceptance criteria

This work is complete when all are true:

- a skill exists under `~/.agents/skills`
- the skill contains co-located templates
- the skill can bootstrap both presets
- generated projects include version, build, and release scaffolding
- generated projects include `CLAUDE.md` plus `AGENTS.md` symlink behavior
- first build succeeds for at least one sample project from each preset
- documentation explains how each preset maps back to reference projects

## 15. Recommendation

Proceed with a self-contained skill in `~/.agents/skills` that owns:

- references
- templates
- bootstrap scripts

and start with exactly two presets:

- `macos-swiftpm-app`
- `macos-xcode-rust-ffi-app`

This is the smallest design that matches the user's stated reuse goal while remaining grounded in the two proven reference projects.
