# macOS Project Bootstrap UI Skeleton Design

## Goal

Extend the `macos-project-bootstrap` skill so the `macos-xcode-rust-ffi-app` preset can generate a neutral, reusable macOS main-window UI skeleton derived from `TokenViewer`'s window structure, without hard-coding `TokenViewer` business concepts.

## Scope

In scope:

- Add a configurable main-window shell for the Xcode + Rust preset
- Accept a user-provided tab list at bootstrap time
- Generate a neutral `TabView`-based macOS window with shared page scaffolding
- Reuse `TokenViewer` layout patterns:
  - persistent main window
  - per-page scrollable content
  - title/subtitle header with trailing actions
  - rounded content surfaces for sections and settings groups
- Document the extracted UI patterns inside the skill

Out of scope:

- Menu bar popover reuse
- Provider icons, provider colors, or `TokenViewer` brand assets
- Chart, metrics, or domain-specific dashboard widgets
- A third visual preset

## Source Patterns From TokenViewer

The abstraction reuses these structural patterns from `TokenViewer`:

- `MainWindowView` uses `TabView` as the primary shell
- Each page is vertically scrollable and padded for desktop scanning
- Top-level pages start with a strong title and short subtitle
- Repeated content is placed in low-radius cards against the window background
- Settings use grouped cards with light section labels

These patterns are structural only. The generated skeleton must not contain `TokenViewer` business labels such as providers, limits, token usage, or currency management.

## User Interface Design

### Bootstrap Input

Add an optional bootstrap parameter:

- `--tabs "Overview,Records,Settings,About"`

Behavior:

- Comma-separated list
- Trim whitespace around each tab name
- Preserve original title casing for visible labels
- Derive stable identifiers and Swift type names from the provided labels
- Use a safe default when omitted:
  - `Overview,Records,Settings,About`

### Generated UI Structure

The generated project will contain:

- `ContentView.swift`
  - thin wrapper that hosts the main window shell
- `MainWindowView.swift`
  - owns `TabView`
  - persists selected tab with `@AppStorage`
- `Models/AppSection.swift`
  - declares the generated tab list
  - maps each tab to an SF Symbol
- `Views/Shared/PageScaffold.swift`
  - standard page container with title, subtitle, and trailing actions
- `Views/Shared/SurfaceCard.swift`
  - neutral content card
- `Views/Shared/SettingsGroupCard.swift`
  - grouped card for settings-style pages
- `Views/Sections/*View.swift`
  - one generated placeholder page per requested tab

### Page Behavior

Each generated page must:

- render inside `ScrollView`
- use the shared page scaffold
- contain 2-3 example content sections
- remain neutral enough to be replaced by downstream product code

Heuristic special cases:

- tabs matching `settings` use `SettingsGroupCard` examples
- tabs matching `about` use app/build metadata placeholders
- all others use generic `SurfaceCard` content

## Script Design

### `bootstrap.sh`

Add:

- `--tabs` option
- usage text describing the option and default

### `render_template.sh`

Add:

- environment propagation for the tab list
- call into a dedicated UI scaffold generator when rendering the Xcode + Rust preset

### New UI Scaffold Generator

Create a dedicated script in the skill:

- `scripts/generate_xcode_rust_ui_scaffold.sh`

Responsibilities:

- parse the tab list
- normalize identifiers
- choose default SF Symbols
- generate section model file
- generate shared UI files
- generate one Swift file per requested tab

This keeps `render_template.sh` focused on generic template rendering.

## References Update

Update the skill references to explain:

- which parts came from `TokenViewer`
- what is intentionally omitted
- how to choose and pass the `--tabs` parameter

Add:

- `references/ui-patterns.md`

## Verification

Validation for this feature is complete only when:

1. the new docs exist
2. the skill help output mentions `--tabs`
3. a generated sample project builds successfully
4. the generated app opens with the neutral tab shell

## Risks

- invalid tab names generating invalid Swift identifiers
- too much generated UI opinion making the preset feel product-specific
- too little structure leaving the preset close to the current empty placeholder

## Mitigations

- sanitize identifiers in one generator script
- keep visual primitives generic and text replaceable
- verify with a fresh generated project instead of only linting the templates
