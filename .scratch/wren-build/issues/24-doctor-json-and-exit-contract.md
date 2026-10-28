# 24: Emit versioned doctor JSON and diagnostic statuses

Status: ready-for-agent
Blocked by: [23: Validate every release with full offline doctor](23-doctor-full-offline-integrity.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren doctor spec](../../wren-doctor/spec.md), [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A script can request one versioned JSON diagnosis for quick or full doctor, including partial findings, and rely on distinct statuses for complete, critical, incomplete, usage, and cancelled runs.

## Acceptance criteria

- [ ] `doctor --json` emits exactly one parseable schema-versioned document on stdout for successful, critical, and incomplete quick or full scans; progress and verbose detail go to stderr.
- [ ] The report keeps integrity, compatibility, selection and its source, setup findings, scan depth, and completion as separate structured dimensions.
- [ ] Complete diagnosis with no critical finding exits `0`; complete diagnosis with critical findings exits `1`; incomplete diagnosis exits `4` even when damage was also confirmed.
- [ ] Syntax errors exit `2` and cancellation exits `6`; informational incompatibility or absence of a selection does not use `3`, and doctor never uses SDK-launch status `5`.
- [ ] CLI tests parse stdout and verify stderr separation, partial results, and status precedence.
