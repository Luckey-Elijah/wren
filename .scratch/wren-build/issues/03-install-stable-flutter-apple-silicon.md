# 03: Install a stable Flutter release on Apple Silicon

Status: complete
Blocked by: [02: Install a stable Flutter release on Linux](02-install-stable-flutter-linux.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A macOS arm64 developer gets the same stable-install behavior with native Apple Silicon artifacts and a release-private SDK, including the same validation and atomic publication guarantees.

## Acceptance criteria

- [x] `install <release>` selects a native macOS arm64 catalog artifact and rejects Intel-only or otherwise unsupported entries before staging.
- [x] The macOS checkout, engine source, bundled Dart, and host tools are validated before the release is marked ready.
- [x] Live SDK files are private to the installed release and no partial macOS stage appears as installed after failure or interruption.
- [x] Host-specific behavior is verified on a macOS arm64 runner or equivalent native environment, with fixture coverage for rejected artifacts.

Verification: `tool/verify.sh` passed on Darwin arm64 using Dart 3.13.4; fixture coverage verifies native macOS publication, isolated live files, failed publication, Intel runtime rejection, and Intel-only catalog rejection before storage is created.
