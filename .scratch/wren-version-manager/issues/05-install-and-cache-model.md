Type: grilling
Status: resolved
Blocked by: 03, 04

## Question

Given the release metadata and Puro findings, which installation and cache model should Wren use? Decide how a version maps to a framework checkout and shared engine/Dart artifacts, how parallel work is coordinated, how installs become atomic, and which assets `remove` may reclaim safely.

## Answer

Wren identifies an install by its catalog release (channel, version, framework commit) and host OS/architecture. It keeps one shared Wren-managed Flutter Git repository and creates a detached linked worktree at that release's framework commit. The framework commit's `bin/internal/engine.version` supplies the distinct engine commit. Wren reads it before checkout completes, starts the host engine/Dart download in parallel with checkout, and lets installs requiring the same engine commit join one download. This adopts the useful sharing and overlap found in [Puro cache techniques](04-puro-cache-techniques.md) without Puro's named environments.

Wren retains downloaded, immutable engine and bundled Dart artifacts as a shared **source** keyed by engine commit, host/architecture, and archive variant. Each release checkout has independent live artifact files, prepared from that source by copy-on-write cloning where supported and byte copying otherwise; it never links live files to the source. Flutter's writable stamps, tool snapshots, and other mutable cache state also remain local. `install` fetches the host artifacts needed to run `flutter` and `dart` before calling the release ready. Device and build-target artifacts fetched by Flutter on first use remain private and are not automatically promoted for cross-release sharing. The full boundary and disk tradeoff are decided in [Shared artifact reuse policy](13-shared-artifact-reuse-policy.md).

The checkout and shared artifact download are staged. Wren verifies the checkout's framework commit and its engine revision, checks downloaded engine artifacts from Flutter's revision-specific HTTPS path against the storage provider's transfer checksum and archive structure, and checks the bundled Dart version and runnable host tools. The [release catalog](../research/release-catalog.md) provides no catalog-pinned digest for separate engine artifacts; Wren does not treat the full SDK archive's SHA-256 as a digest for them. Missing or failed required validation prevents publication. A release becomes visible to `list` and active-release selection only after one atomic ready-state publication. Failed or interrupted stages remain invisible.

Different releases may install concurrently. Wren uses a per-release lock for checkout/publication, a per-engine-artifact lock for a single shared download and promotion, and a short shared-Git mutation lock for fetches and worktree metadata changes. Wren-launched SDK processes hold a use lease for their release-private files until exit; removal waits for those leases. Active installs and repairs protect the shared source they are using, but an SDK process does not read it through its live SDK path.

`remove <release>` deletes that release's worktree and entire release-private cache, then reclaims any shared engine/Dart source with no installed-release or active install/repair references. Sources still referenced elsewhere remain. After removing the last release, Wren asks whether to delete the now-unused shared Flutter Git repository; declining keeps it for a later install. User-visible interruption, repair, and noninteractive prompt behavior belong to [Recovery and lifecycle](08-recovery-and-lifecycle.md). Direct use of SDK paths outside Wren is covered in [External SDK integration](09-external-sdk-integration.md).

## Comments

Decision in progress: Use one shared Flutter Git repository with detached worktrees per release, plus immutable engine/Dart artifact entries shared by engine commit and host architecture. Keep Flutter's writable stamps and tool state local to each checkout. Different release installs may run concurrently. Read the engine revision from the selected framework commit, then overlap framework checkout with the shared engine/Dart download; installs needing the same engine revision join that download. Fetch host tools before marking an install ready; fetch target artifacts on first use. Stage and validate checkout and cache, then publish the release atomically. Engine downloads use HTTPS from Flutter's revision-specific path, the provider's transfer checksum, archive structure, expected engine revision, and bundled Dart version; the release catalog does not supply a pinned digest for these individual artifacts.

Further choices confirmed: `remove` reclaims engine/Dart entries with no installed-release, in-progress-install, or Wren-launched-process users. It asks before deleting the shared Git repository after the last release. Per-release and per-engine locks, a short shared-Git mutation lock, and use leases for Wren-launched SDK processes coordinate installs, launches, and removal; removal waits for those processes to exit.

The shared-cache and SDK-process-lease details in the historical comments are superseded by [Shared artifact reuse policy](13-shared-artifact-reuse-policy.md). The answer above reflects the release-private live artifact model.
