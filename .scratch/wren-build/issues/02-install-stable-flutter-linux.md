# 02: Install a stable Flutter release on Linux

Status: complete
Blocked by: [01: Discover eligible Flutter releases](01-discover-eligible-flutter-releases.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

A Linux x86_64 developer can install one eligible stable Flutter release and receive a usable, release-private SDK. Installation uses the selected framework revision and validates required host artifacts before the release becomes ready.

## Acceptance criteria

- [x] `install <release>` creates a detached release checkout from Wren's managed Flutter Git repository and reads its engine revision from that checkout.
- [x] The native host source and live SDK are staged separately; live Dart, engine, web, package, and mutable cache files belong only to this release.
- [x] Catalog identity, transfer checksum, archive structure, bundled Dart version, and runnable host tools are verified before one atomic ready-state publication.
- [x] Failed or interrupted staging is invisible as an installed release; a later attempt starts from a fresh stage.
- [x] An ineligible release fails before publication with an actionable host, architecture, or Dart-version reason.
