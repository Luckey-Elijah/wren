Type: research
Status: resolved
Blocked by: 13

## Question

How can Wren fulfill [Shared artifact reuse policy](13-shared-artifact-reuse-policy.md)'s `repair` contract for optional device and build-target artifacts that Flutter downloaded privately, including through a direct editor SDK path that Wren did not observe? For supported Flutter releases with bundled Dart >=2.19 on Linux x86_64 and macOS arm64, use first-party Flutter source and small targeted checks to identify a reliable way to discover which optional artifact groups are already present, validate their contents rather than just their stamps, and restore damaged present groups without fetching never-used platforms. Assess whether Flutter's own `precache` machinery can safely do this or whether Wren needs version-aware artifact manifests/allowlists. State any gap that requires a further product decision before the specification is implementation-ready.

## Answer

[Full findings, first-party sources, and a targeted Linux cache-predicate check](../research/optional-artifact-repair-inventory.md). Flutter 3.7.0 and 3.47.0 use stamps and selected path-existence checks for cache freshness; neither checks the bytes of every extracted artifact. The targeted check found that the engine-group predicate still returned true after an interior binary was changed or deleted. Required host and optional target archives can share a destination, so directory existence alone does not establish which optional group was fetched. `precache --force` clears every artifact stamp, downloads into the checkout, and cannot serve as Wren's content validator or atomic repair operation.

Wren would need a version-aware map of each supported release family's artifact groups, archive footprints, postprocessing, and trusted expected file contents. It could then inventory candidate groups from Wren records, stamps, and file footprints, validate against trusted manifests, and stage only needed replacements before publication. Flutter removes downloaded ZIPs after extraction, and its engine metadata does not provide per-file hashes. A group first fetched through a direct editor SDK path has no Wren-recorded digest baseline; fully validating it may require obtaining its source archive or a trusted manifest even when the group is sound. A fully erased group with a missing stamp is indistinguishable locally from one never fetched. External Gradle/Maven caches also need an explicit scope boundary.

That conflicted with the earlier promise that a healthy `repair` downloads nothing while fully validating every present optional group. [Optional artifact repair guarantee after direct SDK use](15-optional-artifact-repair-guarantee.md) resolves the conflict by allowing a trusted fetch for a first-seen, evidenced group and defining ambiguous presence and external-cache boundaries. The two sampled release families establish the gap, not full coverage of every eligible release.
