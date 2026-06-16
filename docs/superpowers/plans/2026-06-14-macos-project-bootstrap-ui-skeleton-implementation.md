# macOS Project Bootstrap UI Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the `macos-project-bootstrap` skill so the Xcode + Rust preset can generate a neutral, configurable main-window UI skeleton based on `TokenViewer` layout patterns.

**Architecture:** Keep the generic bootstrap flow unchanged, but add a tab-list input and a dedicated UI scaffold generator for the Xcode + Rust preset. The generator emits small SwiftUI files for the shell, shared cards, and per-tab placeholders, while the template remains product-neutral.

**Tech Stack:** Bash, SwiftUI, XcodeGen, Rust staticlib preset, shell-based template rendering

---

### Task 1: Document The UI Abstraction

**Files:**
- Create: `docs/superpowers/specs/2026-06-14-macos-project-bootstrap-ui-skeleton-design.md`
- Create: `docs/superpowers/plans/2026-06-14-macos-project-bootstrap-ui-skeleton-implementation.md`
- Create: `/Users/Joy/.agents/skills/macos-project-bootstrap/references/ui-patterns.md`
- Modify: `/Users/Joy/.agents/skills/macos-project-bootstrap/SKILL.md`
- Modify: `/Users/Joy/.agents/skills/macos-project-bootstrap/references/preset-matrix.md`
- Modify: `/Users/Joy/.agents/skills/macos-project-bootstrap/references/reference-projects.md`

- [ ] **Step 1: Add the design spec**

Write the design file describing scope, generated files, script changes, and verification expectations.

- [ ] **Step 2: Add the implementation plan**

Write this plan file with the concrete file list and execution order.

- [ ] **Step 3: Add the UI reference**

Document the extracted `TokenViewer` layout patterns and the intentional exclusions.

- [ ] **Step 4: Update skill entry docs**

Mention the new `--tabs` parameter and note that the Xcode + Rust preset now includes a neutral main-window shell.

- [ ] **Step 5: Review docs for contradictions**

Check that all docs describe the same scope: main window only, no menu bar popover, no product-specific widgets.

### Task 2: Extend Bootstrap Rendering For Tab Configuration

**Files:**
- Modify: `/Users/Joy/.agents/skills/macos-project-bootstrap/scripts/bootstrap.sh`
- Modify: `/Users/Joy/.agents/skills/macos-project-bootstrap/scripts/render_template.sh`
- Create: `/Users/Joy/.agents/skills/macos-project-bootstrap/scripts/generate_xcode_rust_ui_scaffold.sh`

- [ ] **Step 1: Add `--tabs` parsing in `bootstrap.sh`**

Add a default value and usage text for a comma-separated tab list.

- [ ] **Step 2: Pass the tab list through the render environment**

Ensure `render_template.sh` receives `TABS` for downstream generation.

- [ ] **Step 3: Implement the generator script**

Create a script that:
- parses comma-separated labels
- derives Swift-safe identifiers
- maps tabs to default SF Symbols
- writes the section model, shell, shared cards, and section views

- [ ] **Step 4: Hook the generator into template rendering**

Call the generator only for `macos-xcode-rust-ffi-app` targets.

- [ ] **Step 5: Smoke-check the help output**

Run the bootstrap help command and verify `--tabs` appears with the expected default description.

### Task 3: Replace The Empty Xcode Preset UI With The Generated Skeleton

**Files:**
- Modify: `/Users/Joy/.agents/skills/macos-project-bootstrap/templates/macos-xcode-rust-ffi-app/macos/__PROJECT_NAME__/Views/ContentView.swift`
- Create via generator under generated projects:
  - `macos/<App>/Models/AppSection.swift`
  - `macos/<App>/Views/MainWindowView.swift`
  - `macos/<App>/Views/Shared/PageScaffold.swift`
  - `macos/<App>/Views/Shared/SurfaceCard.swift`
  - `macos/<App>/Views/Shared/SettingsGroupCard.swift`
  - `macos/<App>/Views/Sections/*View.swift`

- [ ] **Step 1: Make `ContentView` host the shell**

Reduce the template `ContentView.swift` to a wrapper around `MainWindowView`.

- [ ] **Step 2: Generate the section model**

Emit a compact model and per-section factory so the shell is tab-driven.

- [ ] **Step 3: Generate shared UI primitives**

Emit `PageScaffold`, `SurfaceCard`, and `SettingsGroupCard` with neutral styling.

- [ ] **Step 4: Generate per-tab placeholder views**

Emit one SwiftUI file per requested tab with page-specific placeholder content.

- [ ] **Step 5: Keep settings/about heuristics narrow**

Only apply specialized placeholders for obvious `settings` and `about` tabs; all others stay generic.

### Task 4: Verify With A Fresh Generated Project

**Files:**
- Use generated sample directory under `/tmp`

- [ ] **Step 1: Generate a fresh sample project**

Run:

```bash
rtk /Users/Joy/.agents/skills/macos-project-bootstrap/scripts/bootstrap.sh \
  --preset macos-xcode-rust-ffi-app \
  --target /tmp/macos-rust-ffi-ui-sample \
  --project-name SampleUIShell \
  --display-name "Sample UI Shell" \
  --bundle-id com.example.sampleuishell \
  --rust-crate-name sample_ui_shell_core \
  --tabs "Overview,Library,Settings,About"
```

Expected: project directory exists and first build emits a `.app`.

- [ ] **Step 2: Verify generated files**

Run:

```bash
rtk find /tmp/macos-rust-ffi-ui-sample/macos/SampleUIShell -maxdepth 3 -type f | sort
```

Expected: shared files and section views exist.

- [ ] **Step 3: Run the generated build again explicitly**

Run:

```bash
rtk env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /tmp/macos-rust-ffi-ui-sample/script/build_and_run.sh build
```

Expected: succeeds and produces `DerivedData/Build/Products/Debug/SampleUIShell.app`.

- [ ] **Step 4: Record remaining gaps**

If any generated text, icon mapping, or view naming feels off, fix the generator now instead of leaving the sample half-polished.
