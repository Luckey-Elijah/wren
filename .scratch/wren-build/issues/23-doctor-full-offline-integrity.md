# 23: Validate every release with full offline doctor

Status: complete
Dependencies completed: [16: Repair optional artifacts on Apple Silicon](16-repair-optional-artifacts-apple-silicon.md)
Contract: [Wren doctor spec](../../wren-doctor/spec.md), [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

`wren doctor --full` checks every installed release's locally verifiable integrity offline, reports the strength of evidence, and keeps partial findings when an individual check cannot finish.

## Acceptance criteria

- [x] Full doctor validates checkout identity, retained source, release-private required files, and evidenced optional groups using trusted local expected contents without downloading or launching Flutter or Dart.
- [x] A first-seen optional group without trusted local data is incomplete and points to `wren repair <release>`; stamps alone never imply fully verified.
- [x] Confirmed damage persists needs-repair state, including affected source dependents; timeout or missing evidence alone does not mark damage.
- [x] Progress remains visible during advancing scans; stalled operations time out, other releases continue, and partial findings remain available.
- [x] CLI tests cover healthy, damaged, and unverified groups, mixed damage and timeout, offline behavior, and no SDK file changes.

## Linux partial delivery

- Linux x86_64 full doctor validates checkout identity, retained source contents, release-private payloads, and evidenced optional groups against retained local inventories. Unsupported hosts and unavailable evidence report incomplete; they do not create damage markers.
- At the Linux-only delivery, the Apple Silicon optional-group check remained incomplete pending issue #16. The supported-host completion below supersedes that blocker.
- Confirmed source damage marks the shared source or all dependent releases when the source path cannot safely hold a marker. Confirmed release damage persists a launch-blocking marker. Full doctor remains read-only for SDK payloads and never launches Flutter or Dart.
- `DoctorFullIntegrityReport` exposes per-release identity and checks, plus scan completion separately from integrity, for issue #24's later serializer.
- Verification: `tool/verify.sh` passed on Linux x86_64 with the bundled Dart SDK: formatting clean, analyzer clean, and 103 tests passed. One earlier full run had an unrelated process-cancellation test return `-2`; its isolated retry and the subsequent full run both passed.

## Supported-host completion (2026-10-30)

Implementation commits `a24a8aa` and `c9ef774`, with test-isolation correction `602d3ee`, complete the supported-platform contract after #16. The setup inspector recognizes the installer's `darwin-arm64` release directories instead of falsely classifying sound macOS releases as critical. Full integrity scans bound individual local operations rather than the entire advancing scan; optional stamp reads retain the same operation timeout.

Acceptance audit:

1. CLI tests validate all identity, source, private-file, and optional-group checks for trusted macOS inventories, including iOS, Android, macOS, Linux, Fuchsia, and Flutter runner groups. Flutter 3.7 historical iOS layout also passes. SDK/source snapshots and fetch counters prove inspection does not modify payloads or launch/fetch through Flutter.
2. Before repair establishes expected contents, every evidenced macOS optional group reports incomplete with `wren repair <release>` guidance. The manifest remains unchanged, and no source is fetched. Existing Linux coverage preserves the same guarantee.
3. Confirmed iOS corruption reports needs repair and persists `optionalArtifactsNeedRepair`; source/private snapshots remain unchanged. Existing shared-source and sidecar tests prove dependent propagation, prelaunch blocking, and successful repair recovery. Timeout-only evidence creates no damage marker.
4. A controlled progressing source scan outlasts a 250 ms operation timeout while continuing to report progress and finishes successfully. Existing stalled-Git, mixed timeout/damage, cancellation, and continued-check cases pass.
5. `tool/verify.sh` passes formatting, analysis with no issues, and all 110 tests on both supported native hosts in [GitHub Actions run 41094512708](https://github.com/Luckey-Elijah/wren/actions/runs/41094512708). The [macOS job](https://github.com/Luckey-Elijah/wren/actions/runs/41094512708/job/124196668672) reports image `macos-15-arm64` and Dart `macos_arm64`; the [Linux job](https://github.com/Luckey-Elijah/wren/actions/runs/41094512708/job/124196669230) reports `linux_x64`. The same full verification passes locally on Linux. CI runs this matrix for future PRs.

The CI audit also exposed two SDK selection tests sharing process stdin and user state. Their fixtures explicitly provide empty stdin and temporary stores/projects, preserving their original observable assertions and making the required verification independent of other tests and the user's environment.
