# 13: Repair a damaged retained source

Status: ready-for-agent
Blocked by: [04: List installed releases and basic readiness](04-list-installed-releases-and-readiness.md), [09: Reuse retained shared engine sources](09-reuse-retained-shared-engine-sources.md), [10: Coordinate concurrent installs and retries](10-coordinate-concurrent-installs-and-retries.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A developer can run `wren repair <release>` when its retained shared engine source is damaged. One staged source replacement restores that source and automatically returns dependent releases with sound private files to readiness.

## Acceptance criteria

- [ ] Source damage makes every dependent installed release need repair, even if its own live files are sound; list and prelaunch use the same safety state.
- [ ] Repair fully validates the source, stages and validates a replacement under source coordination, then publishes it without changing any live SDK path.
- [ ] Healthy dependent releases become ready after the source replacement; dependents with damaged private files remain in need of their own repair.
- [ ] Source-only replacement needs no editor-close confirmation; failure or interruption publishes nothing and returns operation status `4`.
- [ ] Tests mutate a retained source shared by multiple releases and verify propagation, one replacement, recovery, and failure behavior.
