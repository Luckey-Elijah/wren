Type: grilling
Status: resolved
Blocked by: 01, 05, 06, 08, 09, 14

## Question

What should bare `wren doctor` check, how deep should it inspect installed releases and Wren setup, and how should it report integrity, project compatibility, selection, incomplete checks, and exit status? The possible `wren doctor <release>` form is a separate design task.

## Answer

Bare `wren doctor` runs offline and does not launch Flutter or Dart. By default it checks every installed release with the same cheap readiness checks as `list` and prelaunch, checks Wren setup, and reports compatibility of every installed release with a `pubspec.yaml` in the current directory when one is present. It reports the effective selection and its reason under Wren's existing precedence. Compatibility and selection are separate from installation integrity. Incompatible releases, including an incompatible effective selection, and the absence of a selected release are informational findings.

`wren doctor --full` validates every installed release using the complete local integrity criteria required by `repair`, including the retained shared artifact source, release-private files, and optional SDK artifacts already present. It does not download, repair, or run an SDK. An optional artifact with no trusted local manifest cannot be called fully verified merely because its stamp exists: report that release as incomplete and suggest `wren repair <release>`. The [separate optional-artifact guarantee](15-optional-artifact-repair-guarantee.md) permits repair to fetch a trusted source and retain validation data for later offline checks.

Report release integrity as **basic checks passed**, **fully verified**, **needs repair**, or **incomplete**, according to checks actually completed. Confirmed damage is the one diagnostic side effect: persist the `needs repair` safety state, including for dependents of a damaged retained shared source, so later launches remain blocked. `doctor` does not modify SDK files, download data, or perform repair. Its next step for a damaged or unverified release can simply be `wren repair <release>`; it need not predict repair operations.

Setup checks cover Wren's executable, registry, storage, global fallback, installed shims, current-process PATH, and availability of required system Git. Report absent optional shim paths and other settings outside Wren's control without treating them as failures; do not claim to validate persistent shell or editor settings. Missing Git is a critical finding because install and repair depend on it. Broken Wren-owned configuration is critical or incomplete according to whether the defect is known or prevents inspection.

Quick checks use short timeouts. A progressing full scan can take longer, but it reports progress and times out stalled operations. A timed-out or otherwise unverified check is incomplete, never damaged solely because it timed out. Continue checking other releases and return partial findings. The human report shows a setup summary, one status line per release, project compatibility and effective selection, plus actionable findings. `--verbose` shows individual check details and retains its existing logging meaning; `--full` alone changes scan depth.

`--json` writes one versioned JSON report to stdout, including partial findings on diagnostic failure. Progress and verbose logs go to stderr, keeping stdout parseable. The data model keeps integrity, project compatibility, effective selection and its source, setup findings, check depth, and completion separate.

Doctor exits `0` when checks complete with no critical findings, even when there are informational incompatibilities or no selected release. It exits `1` for completed diagnosis with critical findings, including any installed release needing repair or missing Git. It exits `4` when diagnosis is incomplete because a check times out or fails internally; `4` takes precedence over `1`. Syntax errors use `2`, and cancellation uses `6`. Doctor does not use SDK-launch status `5` or no-usable-release status `3` for an informational finding.

## Comments

The human confirmed the bare-command contract after several rounds on 2026-10-28 and asked to proceed despite remaining implementation unknowns. The named-release form was floated initially, then explicitly deferred to a separate task so its documentation can be aligned independently.
