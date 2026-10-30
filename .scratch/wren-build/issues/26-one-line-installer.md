# 26: Install Wren with a one-line installer

Status: in progress
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

Developers on Linux x86_64 and Apple Silicon macOS can install the highest
stable Wren release with a curl-to-Bash installer, without `sudo` or shell
startup-file edits.

## Acceptance criteria

- [ ] The installer is published as a GitHub Release asset and documented with a curl-to-Bash command.
- [ ] It selects the highest stable SemVer release and downloads the matching host archive and SHA-256 manifest.
- [ ] It verifies the archive checksum, staged Wren version, and staged `--help` before installation.
- [ ] It safely replaces only a recognized regular Wren executable, preserving the old executable if final validation fails; it refuses symlinks and unknown targets.
- [ ] It installs under `$HOME/.local/bin`, prints PATH guidance without editing startup files, warns if Git is absent, and cleans staged files on failure.
- [ ] Unsupported hosts, download failures, and validation failures produce actionable terminal messages.
