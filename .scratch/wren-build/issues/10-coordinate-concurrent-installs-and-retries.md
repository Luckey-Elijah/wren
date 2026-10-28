# 10: Coordinate concurrent installs and retries

Status: complete
Blocked by: [09: Reuse retained shared engine sources](09-reuse-retained-shared-engine-sources.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

Several Wren processes can install releases safely at once: identical requests cooperate, different releases proceed independently, and failed work can be retried without exposing partial SDKs.

## Acceptance criteria

- [x] Per-release, per-source, and short Git-mutation locks prevent conflicting publication while permitting independent installs to overlap.
- [x] A second install of the same release waits, accepts the first successful install, or starts fresh after the first fails.
- [x] Different releases sharing one source join a single source download; cancellation while waiting returns `6` without stopping the holder.
- [x] Interrupted or failed stages remain invisible; retry discards the affected incomplete stage and starts from scratch.
- [x] Controlled multi-process tests cover contention, joined work, cancellation, failure, and clean retry.
