# Doctor completion and review

Decision record for 2026-10-30 in America/New_York. This page continues the [Linux doctor delivery record](2026-10-28-linux-doctor-delivery.md). The [doctor spec](../wren-doctor/spec.md) and [implementation tickets](../wren-build/issues/) define the contract and acceptance criteria.

## Scope decisions

On 2026-10-30, the user requested completion of the remaining tickets through the chief-of-staff workflow, with a separate worktree for each ticket and GitHub PRs for review. This request supersedes the 2026-10-28 local-only delivery restriction recorded in [Linux doctor delivery](2026-10-28-linux-doctor-delivery.md) and [Ticket execution and rollback](../chief-of-staff/ticket-execution-and-rollback.md). The user did not request PR merges.

As of `Luckey-Elijah/wren@d7607e7`, [#16, Repair optional artifacts on Apple Silicon](../wren-build/issues/16-repair-optional-artifacts-apple-silicon.md), was complete following [PR #2](https://github.com/Luckey-Elijah/wren/pull/2). This supersedes the earlier record that #16 remained excluded and blocked the cross-platform doctor work.

On 2026-10-30, the remaining ticket owners began from `Luckey-Elijah/wren@d7607e7` in separate worktrees. The work covered [#23, Validate every release with full offline doctor](../wren-build/issues/23-doctor-full-offline-integrity.md), and [#24, Emit versioned doctor JSON and diagnostic statuses](../wren-build/issues/24-doctor-json-and-exit-contract.md).

## Verification environment

As of `Luckey-Elijah/wren@d7607e7`, `tool/verify.sh` accepted `DART_BIN` and ran formatting, analysis, and tests. On 2026-10-30, using `/home/apealed/tools/flutter/bin/cache/dart-sdk/bin/dart` avoided the Flutter wrapper's cache writes outside the sandbox. Tests with loopback HTTP fixture servers required execution outside the sandbox. These environment constraints did not change the verification script or acceptance criteria.

## #23 fixes and acceptance evidence

On 2026-10-30, [PR #4](https://github.com/Luckey-Elijah/wren/pull/4) proposed completion of **Validate every release with full offline doctor**. Its implementation commit was [`Luckey-Elijah/wren@a24a8aa`](https://github.com/Luckey-Elijah/wren/commit/a24a8aa).

At that commit, `DoctorSetupInspector` accepted the `darwin-arm64` release-directory name that installation used. Before the fix, setup validation expected `macos-arm64` and reported a critical registry finding for a healthy Apple Silicon installation.

At the same commit, full doctor bounded individual reads, directory streams, hashes, and process waits instead of imposing one fixed deadline on an advancing scan. The new CLI regression completed a scan whose repeated progress updates outlasted the idle timeout. Existing stalled-Git cases retained incomplete findings and continuation behavior. Optional-artifact stamp reads gained a per-read timeout.

The commit added full-doctor checks to the modern macOS optional-artifact lifecycle and the Flutter 3.7 iOS fixture. Assertions covered all evidenced modern target groups before and after trusted inventories existed, confirmed damage, persisted repair markers, visible progress, unchanged SDK payloads, and no SDK launch or fetch. The PR also added `macos-15` to the verification workflow alongside Ubuntu so the full acceptance suite could run on Apple Silicon. On 2026-10-30, local `tool/verify.sh` passed formatting, analysis, and all 110 tests on Linux x86_64 for `a24a8aa`.

On 2026-10-30, [Actions run 41094512708](https://github.com/Luckey-Elijah/wren/actions/runs/41094512708) passed `tool/verify.sh` at `602d3ee` on both supported hosts, with 110 tests on each. The [Apple Silicon job](https://github.com/Luckey-Elijah/wren/actions/runs/41094512708/job/124196668672) reported image `macos-15-arm64` and Dart `macos_arm64`. The [Linux job](https://github.com/Luckey-Elijah/wren/actions/runs/41094512708/job/124196669230) reported `linux_x64`. Commit [`Luckey-Elijah/wren@8f6376d`](https://github.com/Luckey-Elijah/wren/commit/8f6376d) then checked every acceptance criterion, recorded this evidence, and marked ticket #23 complete in PR #4. The PR remained open for user review.

## #24 JSON acceptance evidence

On 2026-10-30, [PR #5](https://github.com/Luckey-Elijah/wren/pull/5) proposed completion of **Emit versioned doctor JSON and diagnostic statuses**. Implementation commit [`Luckey-Elijah/wren@778661d`](https://github.com/Luckey-Elijah/wren/commit/778661d) added macOS JSON acceptance tests. The PR stacked on #23's branch at `8f6376d` because a healthy native-host JSON report depended on the corrected registry check.

At `778661d`, the new CLI cases covered Flutter 3.7 and the modern release fixture. They parsed one schema-versioned document on stdout, checked separate report dimensions, and required verbose detail and full-scan progress on stderr. They exercised quick success, full incomplete evidence, full verified success, full confirmed damage, quick confirmed damage, and incomplete setup with retained damage findings. The cases asserted status 4 precedence over status 1. The existing serializer needed no production change for these cases. On 2026-10-30, local `tool/verify.sh` passed formatting, analysis, and all 112 tests on Linux x86_64 for `7b95184`.

On 2026-10-30, [Actions run 41094645430](https://github.com/Luckey-Elijah/wren/actions/runs/41094645430) passed formatting, analysis, and all 112 tests on both [Linux](https://github.com/Luckey-Elijah/wren/actions/runs/41094645430/job/124197135646) and [Apple Silicon](https://github.com/Luckey-Elijah/wren/actions/runs/41094645430/job/124197136225). The native macOS log identified `macos-15-arm64` and Dart `macos_arm64`. After rebasing the unchanged implementation onto #23's documentation-only completion commit, [`Luckey-Elijah/wren@d227168`](https://github.com/Luckey-Elijah/wren/commit/d227168) recorded the acceptance audit and marked ticket #24 complete. PR #5 remained open, with PR #4 as its review base.

## SDK-selection test isolation

On 2026-10-30, a full verification run exposed an intermittent pre-existing SDK-selection test failure. Stderr identified a closed real stdin descriptor, which produced status 4 before the expected missing-release status 3. Other SDK-launch tests could close shared process stdin when their subscriptions ended. Giving the selection tests temporary directories alone did not fix this failure.

Commit [`Luckey-Elijah/wren@602d3ee`](https://github.com/Luckey-Elijah/wren/commit/602d3ee) supplied explicit empty stdin streams to both selection tests on #23's branch. It also isolated their project and store directories from user state and included stderr in status assertion failures. The status and guidance assertions remained unchanged. The temporary directories removed a separate isolation hazard, rather than the demonstrated closed-stdin cause.

## Independent review

On 2026-10-30, a separate agent inspected #23 commit `a24a8aa` and #24's JSON test diff, finalized at `778661d`. The review followed the full-doctor call graph to confirm that awaited reads, lists, hashes, and process waits retained timeout bounds after removal of the total scan deadline. The review found no additional actionable defect in these changes. This review did not substitute for native CI results.

On the same date, the separate agent reviewed the test-isolation changes later included in `602d3ee` and the progress-fixture analyzer correction in `c9ef774`. The review confirmed that explicit empty stdin, temporary state, and failure diagnostics preserved the existing behavior assertions.
