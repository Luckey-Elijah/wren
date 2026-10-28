# 08: Install beta releases

Status: ready-for-agent
Blocked by: [03: Install a stable Flutter release on Apple Silicon](03-install-stable-flutter-apple-silicon.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A developer can explicitly install an eligible beta Flutter release on either supported host and use the exact bundled Dart prerelease version consistently in metadata and validation.

## Acceptance criteria

- [ ] Beta catalog entries are identified by channel and version and use the full prerelease Dart build SemVer rather than the friendly display base.
- [ ] Both supported hosts install a native beta artifact with the same staged verification and atomic visibility as stable installs.
- [ ] Installed beta Dart is validated against the canonical full version; entries below stable 2.19.0 or with unknown Dart are rejected before staging.
- [ ] Fixture and host tests cover beta selection, version normalization, published identity, and a mismatched bundled Dart executable.
