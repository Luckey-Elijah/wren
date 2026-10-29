# 16: Repair optional artifacts on Apple Silicon

Status: complete
Blocked by: [03: Install a stable Flutter release on Apple Silicon](03-install-stable-flutter-apple-silicon.md), [15: Repair optional artifacts on Linux](15-repair-optional-artifacts-linux.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

macOS arm64 repair gives optional iOS, Android, macOS, and other supported target artifacts the same evidenced-presence, content-validation, and staged-restoration guarantee as Linux.

## Acceptance criteria

- [x] Version-aware inventory covers each supported macOS release family, including host/target archive differences, shared destinations, and nested or postprocessed archives.
- [x] First-seen editor groups can establish trusted expected contents with one group-specific source fetch; later sound repairs use retained validation data.
- [x] Missing or corrupt stamps, distinctive files, retained records, and fully erased unrecorded groups follow the same presence rules as Linux; never-used targets are not fetched.
- [x] Damaged present files are staged and repaired under lease and external-use safeguards; errors do not publish partial files.
- [x] Native macOS arm64 tests exercise the supported iOS, Android, macOS, Linux, Fuchsia, and Flutter runner groups, including Flutter 3.7.0 and 3.47.8 layouts.

## Implementation progress

The shared repair path fetches first-seen target inventories from a detached checkout of the exact framework revision, retains file digests and modes in the release manifest, skips healthy retained groups, and restores damaged or missing files through staged replacements. Exact-version Flutter tooling performs release-specific archive extraction and postprocessing; the audited 3.7 and 3.47 source families share the configured destination roots. Native fixture tests cover evidence from stamps, distinctive paths, and retained records; cancellation and editor confirmation; complete deletion; never-used targets; all supported target groups; and representative Flutter 3.7.0 and 3.47.8 layouts. Windows artifacts are excluded because Flutter does not emit that group for Wren's supported hosts.

After merging current `main`, `tool/verify.sh` passed formatting, analysis, and all 109 tests.
