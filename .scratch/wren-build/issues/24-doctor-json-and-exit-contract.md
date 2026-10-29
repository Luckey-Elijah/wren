# 24: Emit versioned doctor JSON and diagnostic statuses

Status: blocked
Blocked by: [23: Validate every release with full offline doctor](23-doctor-full-offline-integrity.md)
Contract: [Wren doctor spec](../../wren-doctor/spec.md), [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A script can request one versioned JSON diagnosis for quick or full doctor, including partial findings, and rely on distinct statuses for complete, critical, incomplete, usage, and cancelled runs.

## Acceptance criteria

- [ ] `doctor --json` emits exactly one parseable schema-versioned document on stdout for successful, critical, and incomplete quick or full scans; progress and verbose detail go to stderr.
- [x] The report keeps integrity, compatibility, selection and its source, setup findings, scan depth, and completion as separate structured dimensions.
- [x] Complete diagnosis with no critical finding exits `0`; complete diagnosis with critical findings exits `1`; incomplete diagnosis exits `4` even when damage was also confirmed.
- [x] Syntax errors exit `2` and cancellation exits `6`; informational incompatibility or absence of a selection does not use `3`, and doctor never uses SDK-launch status `5`.
- [x] CLI tests parse stdout and verify stderr separation, partial results, and status precedence.

## Linux partial delivery

- Linux x86_64 quick and full modes emit schema-versioned JSON with integrity, compatibility, selection source, setup, depth, and completion kept distinct. Tests cover complete healthy and critical reports, incomplete reports, mixed confirmed damage plus incomplete evidence (exit 4), stderr-only verbose/progress output, usage status 2, cancellation status 6, and no-selection status 0.
- Criterion 1 remains unchecked because full doctor validation is still blocked by issue #23's incomplete supported-platform coverage; this delivery does not claim Apple Silicon behavior.
- Verification on Linux x86_64 after rebasing onto issue #23 commit `f2f920c`: `tool/verify.sh` passed formatting, analysis with no issues, and all 107 tests using the bundled Dart SDK. Focused quick JSON, full JSON, and cancellation tests also passed.
