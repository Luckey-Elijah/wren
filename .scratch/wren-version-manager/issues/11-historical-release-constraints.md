Type: grilling
Status: resolved
Blocked by: 02, 10

## Question

Should Wren's first release install and select historical Flutter releases whose bundled Dart predates 2.19? Dart pub did not accept caret SDK constraints before 2.19, while [Set command and pubspec update](02-set-and-pubspec.md) currently calls for caret constraints whenever `set` rewrites an existing `environment.sdk`. If historical releases are supported, what compatible range form should `set` write for them, and how should Wren explain the exception? If they are excluded, what minimum Flutter/Dart boundary should the release catalog and commands enforce?

## Answer

Wren's first release supports only official Flutter catalog entries with a native artifact for the current host and a known canonical bundled Dart version that compares `>=2.19.0`. This is a Dart-version boundary, not a separate hard-coded Flutter-version floor. Wren uses the full Dart runtime version from [Beta Dart version normalization](10-beta-dart-version-normalization.md), not the catalog's friendly display base. A Dart `2.19.0-*` prerelease is below stable `2.19.0` and is excluded even when its display base reads `2.19.0`; later Flutter betas remain eligible when their actual bundled Dart version meets the boundary. In the inspected [Linux catalog](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json), Flutter 3.7.0 stable with Dart 2.19.0 is eligible, whereas Flutter 3.3.10 with Dart 2.18.6 and Flutter 3.7.0-1.5.pre with Dart 2.19.0-444.6.beta are not.

`wren releases` lists only eligible entries with native artifacts, consistent with [Platforms and distribution](07-platforms-and-distribution.md). `wren install <release>` rejects an entry with older Dart or missing/indeterminate Dart metadata before installation, stating the minimum and the entry's bundled Dart version when known, or naming the missing metadata. Such releases cannot become installed or active through Wren's first-release commands, including `set`/`use`.

Because every admitted release bundles Dart 2.19.0 or newer, `set` keeps the caret constraints for existing `environment.sdk` and `environment.flutter` keys decided in [Set command and pubspec update](02-set-and-pubspec.md). Wren needs no historical explicit-range exception. [Dart's pubspec documentation](https://dart.dev/tools/pub/pubspec#sdk-constraints) states that pub before Dart 2.19 disallowed caret syntax in SDK constraints.

## Comments

Research checked 2026-10-27: [Dart's pubspec documentation](https://dart.dev/tools/pub/pubspec#sdk-constraints) says pub before Dart 2.19 disallowed caret syntax in SDK constraints and gives quoted explicit ranges as the alternative. [Dart's constraint documentation](https://dart.dev/tools/pub/dependencies#version-constraints) equates `^1.3.0` with `'>=1.3.0 <2.0.0'` and says ranges containing `>` must be quoted in YAML. The [official Linux Flutter catalog](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json) pairs Flutter 3.3.10 with Dart 2.18.6 and Flutter 3.7.0 with Dart 2.19.0. It also has beta entries with a displayed Dart 2.19.0 base but a prerelease runtime version, and some older entries omit `dart_sdk_version` entirely (for example, Flutter 1.22.6). The support boundary and resulting `set` form await the user's decision.

The human chose to require Dart 2.19 or newer for Wren's first release. The precise prerelease boundary and treatment of catalog entries with unknown Dart versions are pending.

The human clarified that the canonical bundled Dart version must be at least stable `2.19.0`; `2.19.0-*` prereleases are below the boundary. Catalog entries without a determinable bundled Dart version are excluded rather than probed during installation.

Proposed consolidated resolution, pending shared-understanding confirmation: Wren's first release admits an official Flutter catalog entry only if it has a native artifact for the current host, its canonical bundled Dart version is known, and that version compares `>=2.19.0`. Apply this to stable and beta Flutter entries alike, using the full Dart prerelease build version established by [Beta Dart version normalization](10-beta-dart-version-normalization.md), never the display base. The inspected Linux catalog's Flutter 3.7.0 stable (Dart 2.19.0) passes; Flutter 3.3.10 (Dart 2.18.6) and Flutter 3.7.0-1.5.pre (Dart 2.19.0-444.6.beta) fail. This is a Dart-version rule, not a separate hard-coded Flutter-number floor. `releases` shows only eligible native-host entries, consistent with [Platforms and distribution](07-platforms-and-distribution.md). An explicit `install` of a below-minimum or unknown-Dart entry fails before installation with the specific reason; installed-release selection and `set` cannot select one. Every release Wren admits can use the previously agreed caret form for existing `environment.sdk` and `environment.flutter` keys; no historical explicit-range exception is needed.

The human confirmed the consolidated resolution on 2026-10-27.
