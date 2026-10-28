# 11: Provide stable editor SDK paths

Status: complete
Blocked by: [06: Select a project release and global fallback](06-select-project-release-and-fallback.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

An editor or other external SDK user can ask Wren for a fixed Flutter SDK root for the active or an exact installed release, and Wren remembers that the path may remain in external use.

## Acceptance criteria

- [x] `sdk-path` resolves the active release with normal precedence; `sdk-path <release>` targets that exact installed release.
- [x] On success stdout contains only the fixed real SDK root, and Wren persistently records external use of that release.
- [x] Missing or damaged selections fail with the existing selection or repair status and do not print an unusable path.
- [x] Tests cover exact and active paths, recording persistence, and selection changes without moving a previously printed SDK root.
