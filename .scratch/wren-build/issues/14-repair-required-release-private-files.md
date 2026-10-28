# 14: Repair required release-private files

Status: ready-for-agent
Blocked by: [03: Install a stable Flutter release on Apple Silicon](03-install-stable-flutter-apple-silicon.md), [05: Launch an exact installed release](05-launch-exact-installed-release.md), [11: Provide stable editor SDK paths](11-provide-stable-editor-sdk-paths.md), [13: Repair a damaged retained source](13-repair-damaged-retained-source.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

`wren repair <release>` can fully validate and safely restore damaged required checkout or release-private host SDK files while protecting Wren-launched processes and externally used SDK paths.

## Acceptance criteria

- [ ] Full repair validates the selected release's checkout identity, private host artifacts, bundled Dart, and required tools; a sound release with trusted expected contents needs no download.
- [ ] Damaged private files are replaced from validated sources through a stage, never by exposing a partial live SDK.
- [ ] Repair waits visibly for Wren-launched use leases; if the path has been exposed to an editor, it requests close-editor confirmation before changing live files.
- [ ] Declining or lacking required confirmation returns `6`; failed or interrupted repair returns `4`, publishes nothing, and retains needs-repair state.
- [ ] Tests cover damage, source reuse, staged publication, active leases, external-use confirmation, and unchanged live files after failure.
