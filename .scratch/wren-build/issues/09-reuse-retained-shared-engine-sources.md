# 09: Reuse retained shared engine sources

Status: ready-for-agent
Blocked by: [02: Install a stable Flutter release on Linux](02-install-stable-flutter-linux.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

Installing another release that uses the same engine and native host artifact reuses Wren's retained validated source while every installed release still owns independent live SDK files.

## Acceptance criteria

- [ ] A source is keyed by engine revision and host/archive variant and remains retained while any installed release or active operation references it.
- [ ] Installs sharing a key avoid a second source download and prepare release-private live engine, Dart, web, package, and mutable cache files.
- [ ] Live artifacts never hardlink or symlink to the retained source; copy-on-write cloning may be used with byte-copy fallback.
- [ ] Mutating one release's live cache changes neither the source nor another release's files; tests also exercise source reference retention.
