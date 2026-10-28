Type: grilling
Status: resolved
Blocked by: 14

## Question

What first-release `wren repair` guarantee should apply to optional device and build-target artifacts first fetched through a direct editor SDK path, when Wren has no trusted content manifest? [Optional artifact repair inventory](14-optional-artifact-repair-inventory.md) found that Flutter's stamps and path checks cannot validate their contents. Decide whether full repair may obtain a trusted, version-specific archive or manifest for an already-present group even when it is sound, or instead preserves the no-download healthy path by reporting first-seen groups as not fully verified. Define how repair classifies groups with missing or corrupt stamps, including a fully erased group, and whether external Gradle/Maven caches fall outside Wren's repair scope. Preserve the accepted release-private SDK files, staged publication, and avoidance of downloads for never-used SDK platforms.

## Answer

`wren repair <release>` fully validates optional artifact groups for which it has evidence of presence in that release's Wren-managed SDK cache. A current or stale group stamp, distinctive group-owned files, or a retained Wren inventory record is enough evidence. A stamp alone still counts when payload files are missing; distinctive files still count when the stamp is missing or corrupt. A shared parent directory is not distinctive evidence, because required host and optional artifacts can occupy the same directory. Wren uses a version-aware inventory for the selected Flutter release to interpret these signals and to validate actual contents rather than trusting Flutter's stamp or directory checks.

For a group first fetched through a direct editor SDK path, Wren may obtain that group's trusted, version-specific source archive or file manifest on the first full repair, even when the existing files prove healthy. It validates the group against that source, records the group's identity and expected file contents for later repairs, and keeps the no-download healthy result when all present groups already have trusted expected contents. This narrows the earlier unconditional no-download promise only for first-seen optional groups. It never fetches a group with no evidence of use merely to complete inventory. If the trusted source cannot be obtained or validated, repair cannot report the group healthy; it fails under the existing repair-failure behavior and leaves the release needing repair.

When a group has no stamp, no distinctive files, and no Wren record, Wren treats it as absent and skips it. This also applies if a direct editor fetched the group and then every trace disappeared before Wren observed it; that history is indistinguishable from never having fetched the group. Once Wren validates a group, it retains an inventory record so a later complete deletion is repairable. A damaged present group is restored through staged, release-private replacement under the existing use-lease and external-use confirmation rules. `precache --force` is not used as a full validator or an in-place repair shortcut. Wren's `repair` covers files inside its managed SDK path; external Gradle/Maven caches remain under their own tools' management.

[Optional artifact repair inventory](14-optional-artifact-repair-inventory.md) provides the first-party source evidence and targeted check behind this boundary. Implementation must cover each supported Flutter release family with version-aware artifact footprints and postprocessing; the two researched samples do not prove every eligible release layout.

## Comments

First-round decisions (2026-10-28): For an optional artifact group first fetched through a direct editor SDK path, the first `wren repair` may obtain a trusted, version-specific archive or manifest to verify it even if the group proves healthy. This does not authorize fetching never-used groups. `wren repair` covers Wren-managed SDK files only; external Gradle/Maven caches are outside its scope. Missing-stamp and fully erased-group classification remains open for the next round.

Second-round decisions (2026-10-28): A surviving stamp or distinctive group files each count as evidence that an optional group was present, including when the other signal is missing or corrupt. With no stamp, distinctive files, or prior Wren record, repair skips the group as absent. Wren retains records for groups it has validated so that a later complete deletion remains repairable. These answers settle the remaining frontier for this ticket; the consolidated answer above is the resolution.
