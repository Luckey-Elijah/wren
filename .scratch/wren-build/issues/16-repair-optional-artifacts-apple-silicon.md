# 16: Repair optional artifacts on Apple Silicon

Status: in-progress
Blocked by: [03: Install a stable Flutter release on Apple Silicon](03-install-stable-flutter-apple-silicon.md), [15: Repair optional artifacts on Linux](15-repair-optional-artifacts-linux.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

macOS arm64 repair gives optional iOS, Android, macOS, and other supported target artifacts the same evidenced-presence, content-validation, and staged-restoration guarantee as Linux.

## Acceptance criteria

- [ ] Version-aware inventory covers each supported macOS release family, including host/target archive differences, shared destinations, and nested or postprocessed archives.
- [x] First-seen editor groups can establish trusted expected contents with one group-specific source fetch; later sound repairs use retained validation data.
- [x] Missing or corrupt stamps, distinctive files, retained records, and fully erased unrecorded groups follow the same presence rules as Linux; never-used targets are not fetched.
- [x] Damaged present files are staged and repaired under lease and external-use safeguards; errors do not publish partial files.
- [x] Native macOS arm64 tests exercise iOS, Android, Linux, Windows, and Fuchsia targets, including Flutter 3.7.0 and 3.47.8 layouts.

## Implementation progress

The repair path now fetches first-seen target inventories from an isolated checkout of the exact framework revision, retains file digests and modes in the release manifest, skips healthy retained groups, and restores damaged or missing files through staged replacements. Native fixture tests cover evidence from stamps, distinctive paths, and retained records; cancellation and editor confirmation; complete deletion; never-used targets; all configured target groups; and representative Flutter 3.7.0 and 3.47.8 layouts.

The ticket remains open because the checked-in path-footprint map has not been audited against every supported macOS Flutter release family. The exact-version Flutter checkout supplies archive extraction and postprocessing, but broader source fixtures are still needed to prove the configured roots cover each family's optional artifact destinations.
