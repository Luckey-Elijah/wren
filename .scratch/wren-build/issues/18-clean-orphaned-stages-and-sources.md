# 18: Clean orphaned stages and sources

Status: ready-for-agent
Blocked by: [10: Coordinate concurrent installs and retries](10-coordinate-concurrent-installs-and-retries.md), [13: Repair a damaged retained source](13-repair-damaged-retained-source.md), [14: Repair required release-private files](14-repair-required-release-private-files.md), [17: Remove an installed release safely](17-remove-installed-release-safely.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A developer can preview and reclaim crash-orphaned stages and unreferenced shared sources without threatening installed releases, active operations, or retained recovery data.

## Acceptance criteria

- [x] `cleanup --dry-run` previews provable candidates without deleting them; ordinary `cleanup` reports what it reclaimed.
- [ ] Cleanup removes only stages and sources with no installed-release or active install/repair reference and coordinates with concurrent operations.
- [x] It preserves the optional shared Git repository and Wren's rollback binary and needs no second confirmation.
- [x] Failure returns `4`; tests exercise referenced and active entries, crash orphans, dry-run output, and cancellation of a required wait.

Remaining work: repair tickets 13 and 14 are still unimplemented, so their stage naming and lifecycle locks are not yet available for cleanup integration. This change handles the current install stages and shared source operations; keep this ticket open until cleanup can identify repair stages and verify coordination with active repair operations.
