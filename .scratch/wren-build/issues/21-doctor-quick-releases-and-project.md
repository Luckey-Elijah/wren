# 21: Diagnose releases and project selection quickly

Status: complete
Blocked by: [04: List installed releases and basic readiness](04-list-installed-releases-and-readiness.md), [06: Select a project release and global fallback](06-select-project-release-and-fallback.md), [13: Repair a damaged retained source](13-repair-damaged-retained-source.md), [14: Repair required release-private files](14-repair-required-release-private-files.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren doctor spec](../../wren-doctor/spec.md), [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

Bare `wren doctor` gives a fast, offline human report of every installed release's basic integrity, compatibility with the current project, and the effective release selection with actionable next steps.

## Acceptance criteria

- [x] Quick doctor uses the same cheap readiness checks as list and prelaunch for every registered release, including inactive releases and dependents of a damaged shared source.
- [x] It reports current-directory Flutter and Dart compatibility for each release and the effective selection and source under normal precedence.
- [x] Incompatible alternatives, an incompatible override or fallback, no selected release, and no current-directory project are informational rather than damage.
- [x] Confirmed damage persists the existing needs-repair safety marker; doctor does not launch SDK tools, download artifacts, or repair files.
- [x] Human output has one status line per release and actionable findings; `--verbose` adds check detail without deepening the scan.
