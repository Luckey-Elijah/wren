# 16: Repair optional artifacts on Apple Silicon

Status: ready-for-agent
Blocked by: [03: Install a stable Flutter release on Apple Silicon](03-install-stable-flutter-apple-silicon.md), [15: Repair optional artifacts on Linux](15-repair-optional-artifacts-linux.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

macOS arm64 repair gives optional iOS, Android, macOS, and other supported target artifacts the same evidenced-presence, content-validation, and staged-restoration guarantee as Linux.

## Acceptance criteria

- [ ] Version-aware inventory covers each supported macOS release family, including host/target archive differences, shared destinations, and nested or postprocessed archives.
- [ ] First-seen editor groups can establish trusted expected contents with one group-specific source fetch; later sound repairs use retained validation data.
- [ ] Missing or corrupt stamps, distinctive files, retained records, and fully erased unrecorded groups follow the same presence rules as Linux; never-used targets are not fetched.
- [ ] Damaged present files are staged and repaired under lease and external-use safeguards; errors do not publish partial files.
- [ ] Native macOS arm64 or equivalent host tests exercise the supported target groups and representative historical layouts.
