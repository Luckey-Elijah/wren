# 17: Remove an installed release safely

Status: ready-for-agent
Blocked by: [06: Select a project release and global fallback](06-select-project-release-and-fallback.md), [10: Coordinate concurrent installs and retries](10-coordinate-concurrent-installs-and-retries.md), [11: Provide stable editor SDK paths](11-provide-stable-editor-sdk-paths.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A developer can remove any installed release, including the active or global-fallback release, without deleting files still in use or altering the project's pubspec.

## Acceptance criteria

- [ ] Removal waits for Wren-launched use leases and requests close-editor confirmation for an externally exposed path; cancellation returns `6` without deletion.
- [ ] The release becomes unavailable before file deletion, a matching global fallback is cleared, and the resulting active selection or absence is reported without editing pubspec.
- [ ] Private files and newly unreferenced shared sources are reclaimed only after active operations release them; other releases remain usable.
- [ ] If deletion fails, status `4` leaves the release unavailable and a later `remove` finishes cleanup.
- [ ] The final-release shared Git repository prompt follows the spec; declining or noninteractive use retains that repository while removal succeeds.
