Type: research
Status: resolved
Blocked by: 03, 05

## Question

For Flutter beta catalog entries whose `dart_sdk_version` includes both a display version and a parenthesized build version, what exact Dart version does the bundled SDK report and does pub use for constraint matching? Identify the canonical version Wren should compare with `environment.sdk`, write from `set`, and verify during installation, including any channel or platform exceptions. Use first-party Flutter/Dart sources and a concrete beta example.

## Answer

For beta catalog values such as `3.14.0 (build 3.14.0-315.3.beta)`, the full build SemVer `3.14.0-315.3.beta` is the bundled Dart version used by pub. The leading `3.14.0` is Flutter's friendly display base. Wren should use the full prerelease version for `environment.sdk` matching, write `sdk: ^3.14.0-315.3.beta` when `set` rewrites an existing SDK key, and compare the installed Dart executable's full version token against it before publication. Plain stable SemVer values are used directly. The shared Flutter formatter and pub parser have no host-specific conversion branch; validate every installed host executable. Full first-party source trail and caveats: [beta-dart-version-normalization.md](../research/beta-dart-version-normalization.md).

The separate question of SDK caret syntax for releases bundled with Dart earlier than 2.19 remains open; it does not change which Dart version pub compares.
