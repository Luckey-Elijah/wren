# 19: Package standalone native Wren downloads

Status: complete
Blocked by: [01: Discover eligible Flutter releases](01-discover-eligible-flutter-releases.md), [03: Install a stable Flutter release on Apple Silicon](03-install-stable-flutter-apple-silicon.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A developer on Linux x86_64 or macOS arm64 can obtain and manually install a standalone Wren executable from a versioned release archive with a SHA-256 manifest.

## Acceptance criteria

- [x] Native archives for both supported hosts run without a separately installed Dart SDK and carry versioned, host-specific names and SHA-256 digests.
- [x] Release packaging and manual installation instructions make the required system Git dependency clear.
- [x] The macOS instructions cover any approval step needed for an initially unsigned executable.
- [x] Native-host smoke checks run the packaged executable and a representative command; unsupported hosts are not presented as supported.

Verification: the Linux x86_64 archive built locally, ran `wren --help` and `wren list` from the extracted archive, and passed SHA-256 verification. The release workflow builds and smoke-checks both supported native hosts, including macOS arm64; the macOS runner step was not executed locally.
