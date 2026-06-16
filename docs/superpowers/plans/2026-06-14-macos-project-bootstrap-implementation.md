# macOS Project Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a reusable skill under `~/.agents/skills` that bootstraps macOS project skeletons for SwiftPM apps and Xcode + Rust FFI apps, including build/release scaffolding and first-build validation.

**Architecture:** Keep the skill self-contained. Store the operational instructions in `SKILL.md`, supporting design notes in `references/`, executable bootstrap helpers in `scripts/`, and two project presets in `templates/`. Drive project generation through a shell bootstrap script that renders placeholders and optionally runs a first build.

**Tech Stack:** Shell scripts, template files, SwiftPM, Xcode, Rust cargo, markdown documentation.

---

### Task 1: Initialize the skill skeleton

**Files:**
- Create: `~/.agents/skills/macos-project-bootstrap/`
- Create: `~/.agents/skills/macos-project-bootstrap/SKILL.md`
- Create: `~/.agents/skills/macos-project-bootstrap/agents/openai.yaml`
- Create: `~/.agents/skills/macos-project-bootstrap/references/`
- Create: `~/.agents/skills/macos-project-bootstrap/scripts/`
- Create: `~/.agents/skills/macos-project-bootstrap/templates/`

- [ ] **Step 1: Initialize the skill folder**

Run:

```bash
python3 /Users/Joy/.codex/skills/.system/skill-creator/scripts/init_skill.py \
  macos-project-bootstrap \
  --path /Users/joy/.agents/skills \
  --resources scripts,references,assets \
  --interface display_name="macOS Project Bootstrap" \
  --interface short_description="Bootstrap macOS app projects with build and release scaffolding" \
  --interface default_prompt="Bootstrap a new macOS project from the available presets and validate the first build."
```

Expected: a new `~/.agents/skills/macos-project-bootstrap/` directory exists with the base skill files.

- [ ] **Step 2: Verify the skeleton exists**

Run:

```bash
ls -la /Users/joy/.agents/skills/macos-project-bootstrap
```

Expected: `SKILL.md`, `agents/`, `references/`, `scripts/`, and `assets/` exist.

### Task 2: Write the skill references and operational instructions

**Files:**
- Create: `~/.agents/skills/macos-project-bootstrap/references/architecture.md`
- Create: `~/.agents/skills/macos-project-bootstrap/references/preset-matrix.md`
- Create: `~/.agents/skills/macos-project-bootstrap/references/reference-projects.md`
- Create: `~/.agents/skills/macos-project-bootstrap/references/release-patterns.md`
- Modify: `~/.agents/skills/macos-project-bootstrap/SKILL.md`

- [ ] **Step 1: Write concise reference files**

Add:

- architecture and flow
- preset responsibilities
- mapping back to `ClipboardManager` and `TokenViewer`
- build/release/signing conventions

Expected: reference files contain the non-trivial details, keeping `SKILL.md` lean.

- [ ] **Step 2: Replace the generated `SKILL.md` with the real workflow**

The final `SKILL.md` must:

- use concise YAML frontmatter
- trigger on macOS bootstrap, packaging, release scaffolding, new app setup
- explain when to select each preset
- instruct the agent to read the appropriate reference files only as needed
- point to `scripts/bootstrap.sh` as the deterministic generation path

- [ ] **Step 3: Validate the skill metadata**

Run:

```bash
python3 /Users/Joy/.codex/skills/.system/skill-creator/scripts/quick_validate.py \
  /Users/joy/.agents/skills/macos-project-bootstrap
```

Expected: validation passes with no frontmatter or naming errors.

### Task 3: Add shared bootstrap scripts

**Files:**
- Create: `~/.agents/skills/macos-project-bootstrap/scripts/bootstrap.sh`
- Create: `~/.agents/skills/macos-project-bootstrap/scripts/render_template.sh`
- Create: `~/.agents/skills/macos-project-bootstrap/scripts/verify_env.sh`
- Create: `~/.agents/skills/macos-project-bootstrap/scripts/first_build.sh`

- [ ] **Step 1: Write environment verification first**

Implement `verify_env.sh` to check:

- common: `bash`, `sed`, `find`
- SwiftPM preset: `swift`
- Xcode + Rust preset: `cargo`, `rustc`, `xcodebuild`, `DEVELOPER_DIR` or `/Applications/Xcode.app`

Expected: exits non-zero with a targeted error message when required tools are missing.

- [ ] **Step 2: Write template rendering helper**

Implement `render_template.sh` to:

- copy a preset directory into a target path
- replace `__PROJECT_NAME__`, `__DISPLAY_NAME__`, `__BUNDLE_ID__`, `__APP_EXECUTABLE__`, `__MIN_MACOS_VERSION__`, `__VERSION__`, `__BUILD_NUMBER__`, and `__RUST_CRATE_NAME__`
- create `AGENTS.md` symlink to `CLAUDE.md` in the rendered project when appropriate

Expected: rendering works without external templating dependencies.

- [ ] **Step 3: Write first-build helper**

Implement `first_build.sh` to:

- run preset-specific build commands
- confirm the expected app or binary artifact exists
- print the resulting path

Expected: non-zero exit on build failure, zero on success.

- [ ] **Step 4: Write the top-level bootstrap entrypoint**

Implement `bootstrap.sh` to:

- accept preset and required project parameters
- run `verify_env.sh`
- invoke `render_template.sh`
- invoke `first_build.sh` unless skipped by flag

Expected: one command produces a ready project from a preset.

### Task 4: Add the `macos-swiftpm-app` template

**Files:**
- Create: `~/.agents/skills/macos-project-bootstrap/templates/macos-swiftpm-app/...`

- [ ] **Step 1: Create the minimal project skeleton**

Include:

- `Package.swift`
- `Sources/__PROJECT_NAME__/`
- `Tests/`
- `.gitignore`
- `CLAUDE.md`
- `script/build_and_run.sh`
- `script/release.sh`
- `script/version.env`
- `script/version_utils.sh`
- `docs/releases/`
- `signing/`

Expected: the generated project resembles the reusable parts of `ClipboardManager` without business-specific code.

- [ ] **Step 2: Bake in the shared release contract**

Ensure the template supports:

- local app bundle creation
- zip/pkg/dmg release commands
- version sourcing from `script/version.env`

- [ ] **Step 3: Smoke test rendering**

Run:

```bash
/Users/joy/.agents/skills/macos-project-bootstrap/scripts/bootstrap.sh \
  --preset macos-swiftpm-app \
  --target /tmp/macos-swiftpm-sample \
  --project-name SampleSwiftPMApp \
  --display-name SampleSwiftPMApp \
  --bundle-id com.example.sampleswiftpmapp \
  --skip-first-build
```

Expected: `/tmp/macos-swiftpm-sample` is created with the rendered files and no remaining placeholders.

### Task 5: Add the `macos-xcode-rust-ffi-app` template

**Files:**
- Create: `~/.agents/skills/macos-project-bootstrap/templates/macos-xcode-rust-ffi-app/...`

- [ ] **Step 1: Create the minimal hybrid skeleton**

Include:

- `macos/__PROJECT_NAME__.xcodeproj`
- `macos/__PROJECT_NAME__/...`
- `core/`
- Rust crate setup
- bridging header
- `script/build_and_run.sh` or `run.sh`
- `script/release.sh`
- `script/version.env`
- `script/version_utils.sh`
- `.gitignore`
- `CLAUDE.md`
- `docs/releases/`

Expected: the generated project captures the reusable pattern from `TokenViewer`.

- [ ] **Step 2: Align Rust build output and Xcode link path**

Ensure the template avoids the `SkillSync` mismatch where Debug build logic and static library link path disagree.

Expected: Debug configuration and linked Rust artifact path are internally consistent.

- [ ] **Step 3: Smoke test rendering**

Run:

```bash
/Users/joy/.agents/skills/macos-project-bootstrap/scripts/bootstrap.sh \
  --preset macos-xcode-rust-ffi-app \
  --target /tmp/macos-rust-ffi-sample \
  --project-name SampleRustFFIApp \
  --display-name SampleRustFFIApp \
  --bundle-id com.example.samplerustffiapp \
  --rust-crate-name sample_rust_ffi_app \
  --skip-first-build
```

Expected: `/tmp/macos-rust-ffi-sample` is created with the rendered files and no remaining placeholders.

### Task 6: Verify generated projects and finalize the skill

**Files:**
- Modify: `~/.agents/skills/macos-project-bootstrap/` as needed from validation

- [ ] **Step 1: Run first build for the SwiftPM preset**

Run:

```bash
/Users/joy/.agents/skills/macos-project-bootstrap/scripts/bootstrap.sh \
  --preset macos-swiftpm-app \
  --target /tmp/macos-swiftpm-sample-build \
  --project-name SampleSwiftPMBuild \
  --display-name SampleSwiftPMBuild \
  --bundle-id com.example.sampleswiftpmbuild
```

Expected: first build succeeds and reports an artifact path.

- [ ] **Step 2: Run first build for the Xcode + Rust preset**

Run:

```bash
/Users/joy/.agents/skills/macos-project-bootstrap/scripts/bootstrap.sh \
  --preset macos-xcode-rust-ffi-app \
  --target /tmp/macos-rust-ffi-sample-build \
  --project-name SampleRustFFIBuild \
  --display-name SampleRustFFIBuild \
  --bundle-id com.example.samplerustffibuild \
  --rust-crate-name sample_rust_ffi_build
```

Expected: first build succeeds and reports an artifact path.

- [ ] **Step 3: Re-run skill validation**

Run:

```bash
python3 /Users/Joy/.codex/skills/.system/skill-creator/scripts/quick_validate.py \
  /Users/joy/.agents/skills/macos-project-bootstrap
```

Expected: validation passes after all edits.

- [ ] **Step 4: Inspect for leftover placeholders**

Run:

```bash
rg -n "__[A-Z0-9_]+__" /Users/joy/.agents/skills/macos-project-bootstrap
```

Expected: placeholders appear only inside the template files where intended, not in references or the live skill instructions.
