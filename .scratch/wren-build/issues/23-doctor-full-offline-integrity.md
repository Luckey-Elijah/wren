# 23: Validate every release with full offline doctor

Status: ready-for-agent
Blocked by: [15: Repair optional artifacts on Linux](15-repair-optional-artifacts-linux.md), [16: Repair optional artifacts on Apple Silicon](16-repair-optional-artifacts-apple-silicon.md), [22: Diagnose Wren setup](22-doctor-wren-setup.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren doctor spec](../../wren-doctor/spec.md), [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

`wren doctor --full` checks every installed release's locally verifiable integrity offline, reports the strength of evidence, and keeps partial findings when an individual check cannot finish.

## Acceptance criteria

- [ ] Full doctor validates checkout identity, retained source, release-private required files, and evidenced optional groups using trusted local expected contents without downloading or launching Flutter or Dart.
- [ ] A first-seen optional group without trusted local data is incomplete and points to `wren repair <release>`; stamps alone never imply fully verified.
- [ ] Confirmed damage persists needs-repair state, including affected source dependents; timeout or missing evidence alone does not mark damage.
- [ ] Progress remains visible during advancing scans; stalled operations time out, other releases continue, and partial findings remain available.
- [ ] CLI tests cover healthy, damaged, and unverified groups, mixed damage and timeout, offline behavior, and no SDK file changes.
