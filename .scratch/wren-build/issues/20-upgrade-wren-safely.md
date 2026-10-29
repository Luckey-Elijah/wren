# 20: Upgrade the Wren executable safely

Status: complete
Blocked by: [19: Package standalone native Wren downloads](19-package-standalone-native-wren.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A developer can run `upgrade-wren` to move a direct Wren installation to a newer stable Wren release while retaining a working rollback executable and leaving Flutter installations alone.

## Acceptance criteria

- [x] Upgrade chooses the highest newer stable SemVer from published Wren releases; equal or older versions are a no-op and prereleases or downgrades are excluded.
- [x] It fetches the exact host asset, verifies SHA-256 and the staged executable version, then replaces the current executable atomically while keeping one previous working binary.
- [x] Pre-swap failures leave the current binary untouched; post-swap validation failure restores the previous binary.
- [x] Symlinked, unwritable, or unsuitable executable paths are refused with manual replacement guidance and no elevation request.
- [x] Tests use a fake release source and replaceable executable to cover checksum, no-op, refusal, interruption, and rollback behavior.

Verification: `tool/verify.sh` passed formatting, analysis, and all tests. CLI tests use a local fake release API and replaceable executable fixtures for stable SemVer selection, no-op, checksum mismatch, unsafe paths, interrupted downloads, staged validation, and post-swap rollback. The native packaging smoke check confirmed the compiled version flag.
