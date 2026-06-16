# XcodeGen Assessment For SkillSync

## Decision

Do not migrate `SkillSync` to `project.yml + xcodegen` yet.

## Why

The current project has two concrete issues that block deterministic builds:

1. Debug linked against the release Rust static library
2. Version metadata lacked a sync step between `scripts/version.env` and `project.pbxproj`

Both can be fixed with low-risk changes inside the existing Xcode project. A migration to `xcodegen` would touch the entire macOS build graph, resource declarations, and signing settings at once. That is the wrong change shape while the product is still stabilizing.

## Benefits We Already Captured Without Migration

- Debug and Release Rust artifact paths can now stay aligned in the existing project
- Version metadata can now be synchronized from one source of truth
- Release automation can call the sync step before building

## Revisit Criteria

Revisit `xcodegen` only when at least one of these becomes true:

- frequent manual `.pbxproj` edits are causing merge churn
- the app gains more targets or build variants
- packaging/signing settings need to be templatized across multiple repos
- `SkillSync` itself becomes the canonical source template for new apps

## Current Recommendation

Keep the hand-maintained `SkillSync.xcodeproj` for now. Use the existing `macos-project-bootstrap` skill as the place where `project.yml + xcodegen` stays standardized and reusable.
