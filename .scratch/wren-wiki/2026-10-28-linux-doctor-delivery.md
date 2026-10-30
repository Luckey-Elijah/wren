# Linux doctor delivery

Decision record for 2026-10-28 (America/New_York). This page records the implementation decisions and verified delivery for tickets #22, #23, and #24. The specs and tickets remain the current contracts.

The [2026-10-30 follow-up](2026-10-30-doctor-completion.md) supersedes this page's local-only and excluded-#16 scope decisions. It records #16's integration and the user's request for GitHub PRs for the remaining doctor work. The statements below preserve the 2026-10-28 delivery history.

## User decisions

- Keep the work local. Do not push or publish it.
- Exclude [#16, Repair optional artifacts on Apple Silicon](../wren-build/issues/16-repair-optional-artifacts-apple-silicon.md).
- Deliver honest Linux scope for [#23](../wren-build/issues/23-doctor-full-offline-integrity.md) and [#24](../wren-build/issues/24-doctor-json-and-exit-contract.md), with acceptance gates intact.
- Use Luna at maximum reasoning.
- Commit the wiki separately from ticket code after integration.

## Diagnostic contract

[The doctor spec](../wren-doctor/spec.md) separates installation integrity, project compatibility, effective selection, and scan completion. Missing or untrusted local evidence, a timeout, or another unavailable check means **incomplete**. It does not prove damage. Only confirmed damage can set a needs-repair marker.

Quick doctor stays offline. It does not launch Flutter or Dart or repair SDK files. It reports setup findings alongside release findings.

The setup contract comes from [version-manager decision 16](../wren-version-manager/issues/16-doctor.md). Doctor checks Wren's executable, release registry, storage, configured fallback, installed shims, current-process PATH, and system Git. It treats missing Git and known broken Wren-owned state as critical. Missing optional shims are informational. Unavailable checks are incomplete. Doctor does not claim to inspect persistent shell startup or editor settings.

## #22 delivery

The exact ticket title is **Diagnose Wren setup** ([ticket #22](../wren-build/issues/22-doctor-wren-setup.md)). Ticket #22 is complete. Its implementation is commit `ca3538d1e1d2ccca48f37e7745989f0499272e12` (`feat(doctor): diagnose Wren setup`). The worktree was `/home/apealed/.codex/worktrees/doctor-wren-setup/wren`.

| Acceptance area | Evidence |
| --- | --- |
| Inspect executable, registry, storage, fallback, shims, current PATH, and system Git | `DoctorSetupInspector` is in `../../lib/src/doctor_setup.dart`. CLI tests are in `../../test/wren_test.dart`. |
| Classify known faults as critical, optional absence as informational, and unavailable checks as incomplete | CLI cases cover broken registry and storage, absent and installed shims, missing Git, and stalled Git. |
| Avoid claims about persistent shell and editor state | Setup findings describe the current process and Wren-owned files. `wren doctor` only inspects these items. |
| Bound quick checks and keep reporting other checks with next steps | The stalled-Git CLI case retains registry findings and emits setup findings. The unreadable-registry case retains Storage and System Git findings. |
| Cover setup findings through the CLI | `runWren` tests cover registry and storage, malformed registry identity, executable availability, Git and PATH, installed or absent shims, and timeout continuation. |

The final acceptance audit found one defect after the first attempt. Failure while enumerating installed releases stopped setup diagnostics. The completed commit catches that failure, reports an incomplete registry finding, continues independent setup checks, and returns status 4. The regression is `reports an unreadable release registry and continues setup checks` in `../../test/wren_test.dart`.

Dependencies already present in baseline commit `1b638d2cb2ddcf5e22c6cd78a92f45716f5b83a1` (`Repair optional Linux Flutter artifacts`) include completed [#12](../wren-build/issues/12-set-up-shims-and-editor-guidance.md), [#19](../wren-build/issues/19-package-standalone-native-wren.md), and [#21](../wren-build/issues/21-doctor-quick-releases-and-project.md). The user excluded Apple Silicon artifact repair in #16 from this delivery.

## Pre-implementation safety-marker investigation

This section preserves the plan recorded on 2026-10-28 before #23 implementation, against baseline commit `1b638d2cb2ddcf5e22c6cd78a92f45716f5b83a1`. The #23 delivery section records the implementation and supersedes parts of this plan where the original marker location proved unsafe.

The existing `readiness` and `readinessReason` fields in [`installer.dart`](../../lib/src/installer.dart) were recomputed on each readiness pass. `_readiness` removed both fields and wrote them again from quick observations (baseline lines 1349 to 1358). Quick shared-source checks validated identity, paths, executable modes, and stamps (baseline lines 1424 to 1482). They did not compare retained content digests. A full-doctor hash finding therefore could not rely on those release fields alone.

For confirmed private-file or optional-artifact damage, the plan reused `privateFilesNeedRepair` and `optionalArtifactsNeedRepair`. Baseline `_readiness` respected them (lines 1330 to 1335). The private repair validator cleared its flag only after checking repaired files (lines 2243 to 2273). The optional repair validator did the same (lines 2523 to 2526). Marker helpers were at lines 2955 to 2996.

For confirmed corruption in the retained shared source, the proposed path was a durable non-ready state in `.wren-source.json`, such as `state: needs-repair`, published through `_publishManifest` (baseline lines 3279 to 3288). Each dependent release manifest had a deterministic `sourceKey`. `_quickReadinessReason` rejected source metadata whose state was not `ready` (baseline lines 1431 to 1439). Repair validated the source, rebuilt and revalidated a replacement, then published it ready (baseline source validation at lines 2131 to 2185 and repair flow around lines 541 to 610). Missing trusted evidence or a timeout was not to change marker state.

The baseline test [`repairs one source for all releases without changing live SDKs`](../../test/installer_test.dart) covered dependent propagation and cleanup. Both releases needed repair while their shared source was damaged. After repair, the healthy dependent became ready, while a second release with an independently removed private stamp stayed marked for repair. These baseline code paths informed #23 regression coverage.

## #23 delivery

The exact ticket title is **Validate every release with full offline doctor** ([ticket #23](../wren-build/issues/23-doctor-full-offline-integrity.md)). The Linux partial implementation is commit `f2f920cd934e7ecc05e4829f8f67e88478551631` (`feat(doctor): validate full offline integrity`), based on `1b638d2cb2ddcf5e22c6cd78a92f45716f5b83a1`. Ticket #23 remains blocked only by #16. Criteria 2, 3, 4, and 5 are checked. Criterion 1 remains open because macOS arm64 optional-artifact coverage is incomplete.

On Linux x86_64, `doctor --full` checks registered release identity, retained shared-source contents, release-private payloads, and optional artifact groups supported by trusted local inventories. It does not download data, launch Flutter or Dart, or mutate SDK payloads. `DoctorFullIntegrityReport` keeps per-release integrity separate from whole-scan completion. A timeout or unavailable check stays incomplete. Independently confirmed damage remains visible and can still be marked for repair.

Confirmed private-file and optional-group damage uses `privateFilesNeedRepair` and `optionalArtifactsNeedRepair`. Shared-source damage marks the source manifest when safe. If the source path cannot safely hold a marker, validated dependent release records carry `sourceNeedsRepair`. Unsafe release-record paths use `.wren-doctor-needs-repair.json`. An unsupported host or layout, an untrusted optional stamp, or a timed-out check stays incomplete without adding a damage marker.

Repair tests verify that a source symlink blocks every dependent release until repair rebuilds and validates the shared source, then clears dependent flags. A symlinked release record creates a sidecar that blocks `wren list` and SDK prelaunch. After a trusted regular manifest is restored, `doctor --full` still reports `recorded-needs-repair`. Cancelled repair leaves the sidecar. Successful repair clears it only after validation. To recover from an unsafe or untrusted release record, restore a trusted regular `.wren-release.json` from a known-good copy. Preserve an intentional `externalUse` setting, then run `wren repair <release>`. Leave the safety sidecar in place until repair succeeds.

CLI regressions in [`installer_test.dart`](../../test/installer_test.dart) cover a healthy scan, unsupported host metadata, timeout-only incomplete evidence, an untrusted optional stamp, a trusted Android optional group that stays read-only, mixed timeout and confirmed private damage, marker lifecycles, and no SDK-payload mutation or SDK launch. On a timed-out Git identity probe, cleanup sends TERM, waits 100 ms, then sends KILL and bounds the reap wait to one second.

Unsupported hosts and layouts remain incomplete. The macOS arm64 optional-group check remains incomplete pending [#16, Repair optional artifacts on Apple Silicon](../wren-build/issues/16-repair-optional-artifacts-apple-silicon.md), which the user excluded from this delivery. Linux x86_64 is an honest partial implementation, not completion of the cross-platform acceptance criterion.

`tool/verify.sh` passed at commit `f2f920cd934e7ecc05e4829f8f67e88478551631` on Linux x86_64 with the bundled Dart SDK. Formatting and analysis were clean, and all 103 tests passed. One earlier full run had an unrelated process-cancellation test return `-2`. Its isolated retry and the subsequent full run both passed.

## #24 delivery

The exact ticket title is **Emit versioned doctor JSON and diagnostic statuses** ([ticket #24](../wren-build/issues/24-doctor-json-and-exit-contract.md)). The implementation is commit `a74cadf2a35ac7bedd5b6e9e123d0f55d0c0f6d1` (`feat(doctor): emit versioned JSON diagnosis`), based on #23 commit `f2f920cd934e7ecc05e4829f8f67e88478551631`. Ticket #24 remains blocked by #23. Criteria 2, 3, 4, and 5 are checked. Criterion 1 remains open while full-doctor supported-platform coverage is incomplete.

On Linux x86_64, quick and full `doctor --json` emit one schema-version 1 document on stdout. The report separates setup findings, project compatibility, selection and its source, release integrity, scan depth, and completion. Progress and verbose diagnostics go to stderr. Exit status is 0 for a complete report without critical findings, 1 for a complete report with critical findings, and 4 for an incomplete report even when it also confirms damage. Usage errors return 2. Cancellation returns 6. Informational incompatibility and no selected release do not return SDK-launch status 3 or 5.

The CLI tests parse stdout and verify stderr separation, quick and full reports, mixed damage and incomplete evidence, usage errors, cancellation, no selection, and human-readable verbose behavior. The final integrated `tool/verify.sh` run on Linux x86_64 passed formatting with zero changed files, analysis with no issues, and all 107 tests.

The remaining cross-platform work is to complete #16's Apple Silicon optional-artifact check, then run the full-doctor and JSON acceptance suites on macOS arm64. Unsupported host or layout paths remain incomplete until Wren supports them. #24 remains dependent on closing #23's supported-platform gap.

## #22 verification environment

`tool/verify.sh` passed for #22 commit `ca3538d1e1d2ccca48f37e7745989f0499272e12`: formatting changed no files, analysis reported no issues, and all 100 tests passed. Verification used `/home/apealed/tools/flutter/bin/cache/dart-sdk/bin/dart` because the `dart` wrapper attempted to write under `/home/apealed/tools/flutter`. Verification needed escalation for loopback servers and child processes. The unreadable-registry CLI regression passed on Linux.
