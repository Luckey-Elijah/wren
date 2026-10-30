# 26: Install Wren with a one-line installer

Status: complete
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

Developers on Linux x86_64 and Apple Silicon macOS can install the highest
stable Wren release with a curl-to-Bash installer, without `sudo` or shell
startup-file edits.

## Acceptance criteria

- [x] The release workflow publishes `install.sh` as a GitHub Release asset, and the installer is documented with a curl-to-Bash command.
- [x] It selects the highest stable SemVer release and downloads the matching host archive and SHA-256 manifest.
- [x] It verifies the archive checksum, staged Wren version, and staged `--help` before installation.
- [x] It safely replaces only a recognized regular Wren executable, preserving the old executable if final validation fails; it refuses symlinks and unknown targets.
- [x] It installs under `$HOME/.local/bin`, prints PATH guidance without editing startup files, warns if Git is absent, and cleans staged files on failure.
- [x] Unsupported hosts, download failures, and validation failures produce actionable terminal messages.

Verification: `bash -n install.sh` and `git diff --check` passed. `tool/verify.sh` passed formatting, analysis, and all tests using the stable Dart SDK. Code review found and fixed a missing checkout in the release publish job; follow-up review found no remaining spec mismatch. The installer has not been published to a GitHub Release yet; the release workflow now includes it when a release is published.
