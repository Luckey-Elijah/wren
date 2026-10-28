# 06: Select a project release and global fallback

Status: complete
Blocked by: [05: Launch an exact installed release](05-launch-exact-installed-release.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

Ordinary `wren flutter` and `wren dart` commands choose the correct installed release from the current project or configured global fallback without surprising parent-directory discovery or silent substitution.

## Acceptance criteria

- [x] Selection checks only a pubspec in the current directory and matches both Flutter and bundled Dart environment ranges.
- [x] It chooses the newest fully compatible installed release; beta selection requires explicit prerelease allowance in project constraints.
- [x] When project matching yields no release, the global fallback applies even if it conflicts with constraints; an exact override still wins and never falls back.
- [x] With no usable selected release, SDK commands return `3` and suggest a concrete set or install action rather than prompting.
- [x] CLI tests cover current-directory boundaries, stable/beta constraints, absent or malformed keys, fallback, and exact precedence.
