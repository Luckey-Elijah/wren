# 15: Repair optional artifacts on Linux

Status: complete
Blocked by: [14: Repair required release-private files](14-repair-required-release-private-files.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

Linux x86_64 repair validates and restores optional device or build-target artifact groups that have evidence of use, including a group first downloaded through a direct editor SDK path, without fetching unused targets.

## Acceptance criteria

- [x] The version-aware inventory for supported Linux Flutter release families identifies group-owned files despite overlapping archive destinations and archive postprocessing.
- [x] A current or stale group stamp, distinctive files, or a retained Wren record makes the group present; a shared parent directory alone does not. No evidence means the group is skipped.
- [x] A first-seen present group may fetch only its trusted version-specific archive or manifest, even if sound; validation records expected contents for later download-free checks and complete-deletion repair.
- [x] Changed or missing group files are restored through a private stage under existing lease and editor-confirmation rules; unavailable trusted sources cannot be reported healthy.
- [x] Tests cover historical Linux release families, stamp and file permutations, never-used groups, first-seen editor downloads, corruption, and untouched external Gradle/Maven caches.

## Implementation progress

The Linux-host inventory uses Flutter's exact version-specific Android precache arguments and separate Fuchsia/Flutter runner footprints. Host Linux files remain in required-source validation. Tests cover Flutter 3.7 and 3.47 layouts, direct editor evidence, never-used groups, confirmation, corruption and complete deletion, plus external Gradle/Maven cache sentinels. After merging current `main`, `tool/verify.sh` passed formatting, analysis, and all 109 tests.
