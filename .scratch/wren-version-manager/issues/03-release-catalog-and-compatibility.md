Type: research
Status: resolved

## Question

Which authoritative Flutter release catalogs and metadata provide version, channel, platform/architecture, framework revision, engine revision, bundled Dart version, archive URL, and integrity data needed for `releases`, `install`, and constraint matching? Identify missing fields and reliable ways to obtain them, including prerelease behavior.

## Answer

The official host-specific release JSON supplies version, channel, host artifact, framework revision, bundled Dart version when present, archive URL, and SHA-256 of the complete SDK archive. The engine revision is in the framework ref's `bin/internal/engine.version`. Individual engine artifacts lack a digest in the release catalog. `environment.sdk` constrains bundled Dart, while `environment.flutter` currently enforces only its lower bound in pub. Full findings and citations: [release-catalog.md](../research/release-catalog.md). Historical entries with missing Dart metadata are excluded by [Historical release constraints](11-historical-release-constraints.md).
