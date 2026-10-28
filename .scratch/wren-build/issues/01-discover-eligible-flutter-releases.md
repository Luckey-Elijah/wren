# 01: Discover eligible Flutter releases

Status: ready-for-agent
Blocked by: None (can start immediately)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A developer can run `wren releases` on either supported host and see stable and beta Flutter releases that Wren can install there, with clear reasons when an explicitly requested release is ineligible. This first slice also establishes Wren's command boundary, global `--verbose` handling, and usage errors.

## Acceptance criteria

- [ ] `releases` reads the host catalog and shows only entries with a native artifact and a known canonical bundled Dart version at or above stable 2.19.0.
- [ ] Stable and beta entries retain their channel and version identity; a catalog prerelease build uses its full Dart SemVer for eligibility.
- [ ] Linux x86_64 and macOS arm64 filtering follows native host availability rather than accepting an Intel macOS artifact through Rosetta.
- [ ] CLI usage errors return status `2`; `--verbose` is accepted for Wren commands without changing normal output semantics.
- [ ] CLI-level tests use fixture catalogs for missing Dart metadata, prerelease versions below the floor, and unsupported host artifacts.
