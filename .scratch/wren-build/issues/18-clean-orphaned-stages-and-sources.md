# 18: Clean orphaned stages and sources

Status: complete
Blocked by: [10: Coordinate concurrent installs and retries](10-coordinate-concurrent-installs-and-retries.md), [13: Repair a damaged retained source](13-repair-damaged-retained-source.md), [14: Repair required release-private files](14-repair-required-release-private-files.md), [17: Remove an installed release safely](17-remove-installed-release-safely.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A developer can preview and reclaim crash-orphaned stages and unreferenced shared sources without threatening installed releases, active operations, or retained recovery data.

## Acceptance criteria

- [x] `cleanup --dry-run` previews provable candidates without deleting them; ordinary `cleanup` reports what it reclaimed.
- [x] Cleanup removes only stages and sources with no installed-release or active install/repair reference and coordinates with concurrent operations.
- [x] It preserves the optional shared Git repository and Wren's rollback binary and needs no second confirmation.
- [x] Failure returns `4`; tests exercise referenced and active entries, crash orphans, dry-run output, and cancellation of a required wait.

Completed repair-stage integration: cleanup recognizes source and private-file repair stage names, waits on their per-release install lock, and rechecks each stage before reclaiming it. Tests cover dry-run, orphan reclamation, unknown stage preservation, and cancellation while active repair work holds the lock.
