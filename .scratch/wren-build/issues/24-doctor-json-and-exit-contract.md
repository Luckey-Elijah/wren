# 24: Emit versioned doctor JSON and diagnostic statuses

Status: complete
Dependency completed: [23: Validate every release with full offline doctor](23-doctor-full-offline-integrity.md)
Contract: [Wren doctor spec](../../wren-doctor/spec.md), [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A script can request one versioned JSON diagnosis for quick or full doctor, including partial findings, and rely on distinct statuses for complete, critical, incomplete, usage, and cancelled runs.

## Acceptance criteria

- [x] `doctor --json` emits exactly one parseable schema-versioned document on stdout for successful, critical, and incomplete quick or full scans; progress and verbose detail go to stderr.
- [x] The report keeps integrity, compatibility, selection and its source, setup findings, scan depth, and completion as separate structured dimensions.
- [x] Complete diagnosis with no critical finding exits `0`; complete diagnosis with critical findings exits `1`; incomplete diagnosis exits `4` even when damage was also confirmed.
- [x] Syntax errors exit `2` and cancellation exits `6`; informational incompatibility or absence of a selection does not use `3`, and doctor never uses SDK-launch status `5`.
- [x] CLI tests parse stdout and verify stderr separation, partial results, and status precedence.

## Linux partial delivery

- Linux x86_64 quick and full modes emit schema-versioned JSON with integrity, compatibility, selection source, setup, depth, and completion kept distinct. Tests cover complete healthy and critical reports, incomplete reports, mixed confirmed damage plus incomplete evidence (exit 4), stderr-only verbose/progress output, usage status 2, cancellation status 6, and no-selection status 0.
- At the Linux partial delivery, criterion 1 remained unchecked because issue #23's supported-platform coverage excluded Apple Silicon. The supported-host completion below supersedes that limitation.
- Verification on Linux x86_64 after rebasing onto issue #23 commit `f2f920c`: `tool/verify.sh` passed formatting, analysis with no issues, and all 107 tests using the bundled Dart SDK. Focused quick JSON, full JSON, and cancellation tests also passed.

## Supported-host completion (2026-10-30)

- Both Flutter 3.7.0 and 3.47.8 macOS arm64 fixtures exercise quick and full JSON reports through `runWren`: healthy installations, optional groups without trusted evidence, validated optional groups, confirmed damage, and incomplete setup alongside damage. Each run parses exactly one schema-versioned stdout document and checks progress or verbose detail on stderr.
- The macOS cases verify integrity, project compatibility, effective selection and its source, setup, scan depth, and completion separately. Existing CLI tests cover full-scan partial findings and exit precedence, usage status 2, cancellation status 6, and informational selection status 0.
- Issue #23 fixes the false registry finding for valid macOS release directories and the full-scan idle timeout. The serializer needs no platform-specific change.
- Local `tool/verify.sh` passed formatting, analysis, and all 112 tests on Linux x86_64. [CI run 41094645430](https://github.com/Luckey-Elijah/wren/actions/runs/41094645430) passed the same checks and all 112 tests on Ubuntu and native macOS arm64. The macOS log identifies `macos-15-arm64` and Dart running on `macos_arm64`.
- Implementation and native acceptance evidence are in [PR #5](https://github.com/Luckey-Elijah/wren/pull/5), stacked on [issue #23's PR #4](https://github.com/Luckey-Elijah/wren/pull/4).
