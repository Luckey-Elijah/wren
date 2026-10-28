# 04: List installed releases and basic readiness

Status: ready-for-agent
Blocked by: [02: Install a stable Flutter release on Linux](02-install-stable-flutter-linux.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A developer can see every installed Flutter release and whether Wren currently considers it ready or needing repair, using the same inexpensive signals later used before SDK launch.

## Acceptance criteria

- [ ] `wren list` and `wren ls` report the same installed releases, identities, and known readiness.
- [ ] Cheap checks cover recorded framework and engine identity, source readiness metadata, required files and modes, cache boundaries, and stamp coherence without hashing every artifact.
- [ ] Confirmed missing or invalid required state leaves the release registered and marks it as needing repair; no different release is silently substituted.
- [ ] Tests distinguish a healthy installation, confirmed damage, and an incomplete stage that must not appear in the list.
