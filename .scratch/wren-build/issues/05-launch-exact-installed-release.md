# 05: Launch an exact installed release

Status: ready-for-agent
Blocked by: [04: List installed releases and basic readiness](04-list-installed-releases-and-readiness.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A developer can explicitly choose an installed release and run its `flutter` or `dart` executable transparently, with predictable failure when that exact release is unavailable.

## Acceptance criteria

- [ ] CLI `--release` and `WREN_FLUTTER_RELEASE` select an exact installed release; the CLI value wins when both exist.
- [ ] Every token after `flutter` or `dart` reaches the child unchanged, including apparent Wren flags and `--`; stdin, stdout, stderr, and numeric exit status pass through.
- [ ] A signaled child reports `128 + signal`; a process-start failure reports `5`; missing or detected-damaged exact selections report `3` with repair or install guidance.
- [ ] Launch holds a release use lease until the child exits, and prelaunch readiness agrees with the cheap list criteria.
- [ ] CLI tests use controlled child executables to verify forwarding, streams, status, signals, and lease lifetime.
