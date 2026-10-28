# 07: Set project constraints and the global fallback

Status: complete
Blocked by: [06: Select a project release and global fallback](06-select-project-release-and-fallback.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A developer can use `set` or `use` to express the selected Flutter and bundled Dart versions through existing project constraints and optionally set the global fallback, while seeing the actual selection afterward.

## Acceptance criteria

- [x] `set <release>` and the exact `use` alias rewrite only existing `environment.flutter` and `environment.sdk` keys as caret ranges; they do not create a pubspec or missing keys.
- [x] A Dart major or minor lower-bound change is shown and confirmed before either project or fallback state is written; decline or unavailable noninteractive confirmation leaves both unchanged and returns `6`.
- [x] `-g` sets the fallback and performs the same pubspec edit when one is present; without a pubspec it can set the fallback alone.
- [x] Output reports overwritten constraints and the active release under normal selection rather than implying a project pin.
- [x] Tests inspect resulting YAML and fallback state for stable and prerelease versions, conflicts, missing keys, and confirmation paths.
