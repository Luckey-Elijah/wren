# 23: Validate every release with full offline doctor

Status: blocked
Blocked by: [16: Repair optional artifacts on Apple Silicon](16-repair-optional-artifacts-apple-silicon.md)
Contract: [Wren doctor spec](../../wren-doctor/spec.md), [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

`wren doctor --full` checks every installed release's locally verifiable integrity offline, reports the strength of evidence, and keeps partial findings when an individual check cannot finish.

## Acceptance criteria

- [ ] Full doctor validates checkout identity, retained source, release-private required files, and evidenced optional groups using trusted local expected contents without downloading or launching Flutter or Dart.
- [x] A first-seen optional group without trusted local data is incomplete and points to `wren repair <release>`; stamps alone never imply fully verified.
- [x] Confirmed damage persists needs-repair state, including affected source dependents; timeout or missing evidence alone does not mark damage.
- [x] Progress remains visible during advancing scans; stalled operations time out, other releases continue, and partial findings remain available.
- [x] CLI tests cover healthy, damaged, and unverified groups, mixed damage and timeout, offline behavior, and no SDK file changes.

## Linux partial delivery

- Linux x86_64 full doctor validates checkout identity, retained source contents, release-private payloads, and evidenced optional groups against retained local inventories. Unsupported hosts and unavailable evidence report incomplete; they do not create damage markers.
- The Apple Silicon optional-group check remains incomplete until issue #16 is complete, so acceptance criterion 1 remains unchecked and this ticket stays blocked.
- Confirmed source damage marks the shared source or all dependent releases when the source path cannot safely hold a marker. Confirmed release damage persists a launch-blocking marker. Full doctor remains read-only for SDK payloads and never launches Flutter or Dart.
- `DoctorFullIntegrityReport` exposes per-release identity and checks, plus scan completion separately from integrity, for issue #24's later serializer.
- Verification: `tool/verify.sh` passed on Linux x86_64 with the bundled Dart SDK: formatting clean, analyzer clean, and 103 tests passed. One earlier full run had an unrelated process-cancellation test return `-2`; its isolated retry and the subsequent full run both passed.
