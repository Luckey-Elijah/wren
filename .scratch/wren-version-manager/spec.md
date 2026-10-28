# Wren Flutter and Dart version manager

## Problem Statement

Wren is currently a default Dart CLI starter. Users need a reliable way to install and switch between Flutter releases and their bundled Dart SDKs on supported machines, while allowing project constraints, CI, shells, and editors to choose an appropriate installed release. Flutter SDKs mutate their caches during normal use, and editors can access SDK files directly, so installations must remain isolated and recoverable even when releases share downloaded sources.

## Solution

Turn Wren into a standalone native version-manager CLI for Linux x86_64 and macOS arm64. It discovers eligible Flutter releases, installs selected stable or beta releases atomically, chooses an active release from an exact override, current-directory pubspec constraints, or global fallback, and exposes transparent Flutter/Dart commands plus stable editor paths and optional PATH shims. It retains validated shared artifact sources while keeping all live SDK files private to each installed release. Offline `doctor` diagnostics inspect installations, setup, and project compatibility. Explicit repair, removal, cleanup, and Wren self-upgrade commands manage lifecycle and recovery. Wren's command tree follows familiar Dart CLI conventions so contributors can add and maintain subcommands consistently.

## User Stories

1. As a developer, I want to see installable Flutter releases for this host, so that I can choose a version Wren can actually run.
2. As a developer, I want `wren releases` to include stable and beta releases that meet the supported Dart floor, so that I can discover supported prerelease builds.
3. As a developer, I want catalog entries with unknown bundled Dart versions excluded, so that Wren never offers releases it cannot safely match or validate.
4. As a developer, I want `wren install <release>` to explain host, architecture, or minimum-Dart incompatibility, so that failed selections are actionable.
5. As a developer, I want to install stable or beta Flutter releases by version, so that I can work with production or prerelease SDKs.
6. As a developer, I want Wren to verify the release catalog archive and framework identity, so that a partial or mismatched installation is never presented as ready.
7. As a developer, I want the bundled Dart version checked against the canonical full runtime version, including beta build suffixes, so that pub constraints and installed SDK metadata agree.
8. As a developer, I want releases installed concurrently without corrupting shared state, so that independent setup work can proceed efficiently.
9. As a developer, I want interrupted installs to remain invisible and retry from a clean stage, so that an incomplete SDK is never selected.
10. As a developer, I want `wren list` and `wren ls` to show installed versions and readiness, so that I can see what is available and what needs repair.
11. As a developer, I want Wren to select the newest installed release compatible with both current-project Flutter and Dart constraints, so that ordinary commands use an appropriate SDK.
12. As a developer, I want project discovery limited to the current directory's pubspec, so that Wren does not unexpectedly inherit a parent project's selection.
13. As a developer, I want beta releases automatically selected only when project constraints explicitly allow prereleases, so that ordinary stable constraints do not drift onto beta SDKs.
14. As a developer, I want the global fallback used when no compatible project release exists or no current-directory pubspec exists, so that commands still have a predictable selection.
15. As a developer, I want an exact release override to win over constraints and the global fallback, so that CI and one-off commands can select deterministically.
16. As a developer, I want a missing or unusable exact selection to fail without silently falling back, so that automation cannot run against an unintended SDK.
17. As a developer, I want an installed release that conflicts with project constraints to run when explicitly selected, so that Flutter or Dart can report its normal compatibility error.
18. As a developer, I want `wren set <release>` to rewrite only existing Flutter and Dart environment keys as caret constraints, so that Wren does not invent project policy fields.
19. As a developer, I want `wren set` to report overwritten constraints and the resulting active release, so that I understand the effect even though no project pin is written.
20. As a developer, I want a major or minor Dart lower-bound change confirmed before writing, so that a language-version change is deliberate.
21. As a developer, I want declining that confirmation to leave both pubspec and global fallback unchanged, so that the command is atomic from the project's perspective.
22. As a developer, I want `wren set -g` and `wren use -g` to update the global fallback and perform the same pubspec edit when a pubspec exists, so that one command can configure both scopes.
23. As a developer, I want `wren use` to be an exact alias of `wren set`, so that either familiar command behaves identically.
24. As a developer, I want `wren flutter` and `wren dart` to forward every trailing token unchanged and preserve child streams and exit status, so that Wren remains transparent to SDK tools.
25. As a developer, I want SDK commands to fail immediately with a selection or repair instruction when no usable release is selected, so that a command never silently chooses another SDK.
26. As a developer, I want distinct exit statuses for usage, no usable release, operation failure, launch failure, and cancellation, so that scripts can respond predictably.
27. As a developer, I want `--verbose` on Wren commands without changing SDK arguments or output, so that I can diagnose Wren behavior while preserving SDK semantics.
28. As a shell user, I want `wren setup` to create optional Flutter and Dart PATH shims and print setup steps, so that I can use Wren-managed SDKs in ordinary shell workflows.
29. As an editor user, I want `wren sdk-path` to print the active fixed SDK root and remember external use, so that my editor can use the SDK without a daily protect/unprotect workflow.
30. As an editor user, I want an explicit `sdk-path <release>` to print that release's fixed root, so that JetBrains-style SDK settings can target a stable path.
31. As a VS Code user, I want setup guidance for resolving the Flutter SDK path through Wren at workspace discovery, so that the editor follows the current workspace selection after reload.
32. As an editor user, I want `remove` or private-file repair to ask me to close editors when the release has been exposed, so that Wren does not replace files still in use.
33. As an editor user, I want declined or unavailable external-use confirmation to return cancellation status, so that noninteractive tools do not mutate files an editor may use.
34. As a developer, I want each release's live engine, Dart, web, package, and mutable cache files isolated from other releases, so that Flutter writes and direct editor use cannot corrupt another release.
35. As a developer, I want later installs to reuse a validated engine artifact source when safe, so that repeated installs avoid downloading the same engine payload.
36. As a developer, I want removal to reclaim unreferenced private files and shared sources while retaining anything still referenced by another release or active operation, so that cleanup is safe.
37. As a developer, I want `wren repair` to validate and stage source and private-file replacements before publication, so that repair never exposes partial files.
38. As a developer, I want source-only repair to restore dependent releases whose private files are healthy, so that one recovered source can make several installations ready again.
39. As a developer, I want repair to check optional platform artifacts already present without downloading never-used target artifacts, so that repair respects the release's existing cache footprint.
40. As a developer, I want a damaged installed release to remain registered as needing repair and fail launch with a repair instruction, so that damage is visible and never silently masked by fallback selection.
41. As a developer, I want `wren cleanup --dry-run` to preview abandoned stages and unreferenced sources, so that I can inspect reclamation before running it.
42. As a developer, I want cleanup to remove only provable orphans and preserve the shared Git repository and Wren rollback binary, so that recovery data remains available.
43. As a developer, I want concurrent operations to wait visibly for relevant locks or SDK process leases and allow Ctrl-C to cancel only my wait, so that coordination is understandable and safe.
44. As a developer, I want `wren remove` to support active and global-fallback releases while clearing a removed global fallback, so that deliberate removal remains possible without changing project files.
45. As a developer, I want `wren upgrade-wren` to update only to a newer stable Wren release after checksum, version, and executable validation, so that Wren can update itself safely.
46. As a developer, I want a retained previous Wren binary and rollback after post-swap validation failure, so that self-upgrade preserves a working CLI.
47. As a developer, I want self-upgrade to refuse unsuitable or symlinked executables and print manual replacement guidance, so that it does not request elevated privileges or replace an unintended target.
48. As a developer, I want Wren distributed as standalone native executables with documented manual installation, so that Wren does not require a separate Dart SDK or installer service.
49. As a developer, I want `wren doctor` to quickly inspect every installed release, Wren setup, and current-project compatibility, so that I can understand my environment and next steps without a long scan.
50. As a developer, I want `wren doctor --full` to validate installed SDK integrity offline and report checks it cannot complete, so that a release is never called fully verified on partial evidence.
51. As a developer, I want a versioned `wren doctor --json` report and distinct diagnostic exit statuses, so that scripts can consume complete or partial findings reliably.
49. As an editor user, I want repair to validate optional SDK artifacts my editor downloaded directly, so that I can detect and recover corruption even when Wren did not observe the download.
52. As a Wren contributor, I want commands to use Dart's established command-runner conventions, so that I can understand and extend the CLI without learning a bespoke dispatch pattern.
53. As a Wren contributor, I want shared run configuration and services exposed through a typed Wren context, so that commands use consistent values and services for one invocation.

## Implementation Decisions

### Supported releases and hosts

- The first release supports Linux x86_64 and macOS arm64 only. Flutter installs must use a native host artifact; Apple Silicon does not use Intel artifacts through Rosetta.
- Wren itself is a standalone native executable for each supported host, distributed as versioned GitHub Release archives with SHA-256 manifests and manual installation instructions. The initial macOS build may be unsigned; document any required approval step.
- System Git is required for the shared Flutter repository and linked worktrees. Operations requiring Git preflight a usable Git executable and report installation guidance if missing.
- A Flutter catalog entry is eligible only when the current host has a native artifact and its canonical bundled Dart version is known and at least stable `2.19.0`. This compares the full SemVer, so `2.19.0-*` is below the floor. `releases` omits ineligible entries; explicit installation fails before staging with the reason.
- Flutter release catalog metadata identifies channel, version, framework revision, host archive, and whole-archive SHA-256. The engine revision comes from the engine metadata file in the selected framework revision. A full Flutter archive digest is never reused as a digest for a separate engine archive.
- For catalog values shaped like `<display-base> (build <full-prerelease>)`, the full prerelease SemVer is the canonical Dart version for compatibility, `set`, and install validation. Stable bare SemVer values are used directly.

### Release selection and project configuration

- Precedence is explicit CLI `--release`, then `WREN_FLUTTER_RELEASE`, then current-directory pubspec constraints, then global fallback. The CLI override wins over the environment override. An exact selection bypasses constraint matching and never falls back if missing or unusable.
- Project discovery checks only `pubspec.yaml` in the current working directory. A candidate must satisfy the full `environment.flutter` range and bundled Dart must satisfy `environment.sdk`; choose the newest fully compatible installed release. Beta candidates require explicit prerelease allowance in the project constraints.
- If no compatible project release exists, use the configured global fallback even if it conflicts with project constraints. Use the global fallback also when no current-directory pubspec exists. With no selected release, SDK commands fail with status `3` and a suggested `set` or install action; there is no interactive release-selection prompt.
- `set <release>` rewrites only existing `environment.flutter` and `environment.sdk` keys, each as a caret range at the selected Flutter or canonical Dart version. It does not create a pubspec or missing keys. Without a pubspec, ordinary `set` fails. Selecting a release permits replacing conflicting constraints, which Wren reports.
- If the SDK constraint lower bound changes Dart major or minor, show the proposed change and require confirmation before either pubspec or fallback is written. A decline or unavailable prompt returns status `6`. Patch-only changes and other conflicts need no confirmation.
- `set -g <release>` performs the same pubspec edit when a pubspec is present and sets the global fallback; without a pubspec, it can set the fallback alone. After mutation, report the actual active release under normal resolution. No project pin is written. `use` and `-g` are exact aliases/semantics.

### Installation, cache, and readiness

- Identify an installed release by catalog channel, Flutter version, framework commit, and host OS/architecture. Maintain one Wren-managed Flutter Git repository and a detached linked worktree per release.
- Read engine revision from the selected framework commit, overlap host engine/Dart source download with checkout, and let installs for the same engine revision/host/archive key join one download. Different release installs may run concurrently.
- Use per-release locks for checkout/publication, per-source locks for shared downloads and promotion, and a short Git mutation lock for fetch/worktree metadata. A second install of the same release waits; it accepts the first successful install or starts fresh after failure.
- Stage checkout and artifacts, verify framework commit, engine revision, transfer checksum and archive structure, expected canonical Dart version, and runnable host tools. No install is ready until one atomic ready-state publication. Failed/interrupted stages remain invisible. A retry discards its incomplete stage and starts over.
- Retain one validated immutable engine artifact source keyed by engine revision and host/archive variant while referenced by an installed release or active install/repair. Prepare every live artifact from the source as release-private files, using filesystem copy-on-write cloning where available and byte-copy fallback. Never hardlink or symlink a live SDK artifact to a shared source.
- Engine, bundled Dart, web, package artifacts, stamps, snapshots, downloads, and other mutable Flutter cache state reachable from an installed SDK path remain private to that release. Device/build-target artifacts fetched on first use remain private and are not promoted automatically.
- On filesystems without copy-on-write cloning, accept one retained source plus one extracted live copy per release. Reclaim a source after its final installed-release or active operation reference is gone.
- Cheap list/prelaunch checks validate recorded identities, source readiness metadata, required files/executable modes, cache boundary, link type/target if any links are used, and private stamp coherence; they do not hash every artifact. SDK launch holds a release use lease until child exit.
- A source found damaged makes each dependent release “needs repair” even if private files are sound. Full repair validates sources and private files, stages replacements, and repairs damaged private files for the target. Once a source is repaired, dependent releases whose private files validate become ready automatically.
- Full repair checks an optional artifact group when its group stamp, distinctive group-owned files, or a retained Wren inventory record shows that it was present. A stamp counts even if payload files are missing; distinctive files count even if the stamp is missing or corrupt. A shared parent directory alone is not evidence. If none of those signals exists, repair treats the group as absent and does not fetch it. This includes a group fetched by a direct editor and then fully erased before Wren could observe it.
- Use a version-aware artifact inventory for each supported Flutter release family to validate actual file contents and restore damaged present groups. For a first-seen group fetched through a direct editor SDK path, repair may fetch that group's trusted, version-specific source archive or file manifest even if the group proves healthy. After validation, retain its identity and expected contents so later healthy repairs need no download and complete deletion remains repairable. If the trusted source cannot be obtained or validated, repair cannot report success. Stage release-private replacements before publication; Flutter's `precache --force` is not a full validator or an in-place repair path.

### Doctor and diagnostics

- Bare `wren doctor` runs offline and does not launch Flutter or Dart. Quick mode checks every installed release with the same readiness checks as `list` and prelaunch. `--full` validates every installed release with the complete locally available integrity criteria required by `repair`, including the retained shared source, release-private files, and optional SDK artifacts already present. Neither mode downloads or repairs files.
- Release integrity is reported as **basic checks passed**, **fully verified**, **needs repair**, or **incomplete**, according to checks actually completed. Integrity, project compatibility, and effective selection are independent dimensions. Confirmed damage is persisted as a `needs repair` safety marker, including on releases dependent on a damaged shared source; this is doctor's only state change. A timeout or unavailable trusted validation data is incomplete, not proof of damage. Suggest `wren repair <release>` without predicting its exact repair operations.
- In a directory with `pubspec.yaml`, report each installed release's compatibility with the project's Flutter and bundled Dart constraints. Report the effective selection and its source using normal selection precedence. An incompatible release, including the effective selection, and no selected release are informational doctor findings; SDK launch behavior remains unchanged. With no current-directory project, project compatibility is not applicable.
- Check Wren's executable, registry, storage, global fallback, installed shims, current-process PATH, and required system Git. Missing optional shim paths and settings outside Wren's control are reported without failing diagnosis; do not claim to validate persistent shell or editor settings. Missing Git and confirmed broken Wren-owned configuration are critical findings. If configuration cannot be inspected, report it as incomplete.
- Quick checks use short timeouts. Full validation reports progress while advancing and times out stalled operations. Continue through other releases after an incomplete check, retaining partial results. Do not mark a release damaged solely because a check timed out.
- The human report shows a setup summary, one integrity line per release, project compatibility and effective selection, and actionable findings. `--verbose` adds individual check details without changing scan depth; `--full` changes depth. `--json` emits one versioned JSON report on stdout, even for critical or incomplete results, while progress and verbose logs go to stderr. Model integrity, compatibility, selection and its source, setup findings, check depth, and completion separately.
- Doctor exits `0` for a completed diagnosis with no critical findings, including informational incompatibilities or no selected release; `1` for completed diagnosis with critical findings such as a release needing repair or missing Git; `4` for incomplete diagnosis due to timeout or internal check failure, taking precedence over `1`; `2` for usage errors; and `6` for cancellation. It does not use `3` merely because selection is absent or incompatible, and it never launches an SDK so does not use `5` for an SDK launch failure.
- Offline full validation cannot call an optional artifact first fetched through a direct editor SDK path fully verified when no trusted local manifest exists. Report the affected release as incomplete and suggest repair. The [optional-artifact guarantee](issues/15-optional-artifact-repair-guarantee.md) permits repair to fetch a trusted source and retain validation data for future offline checks. The possible `doctor <release>` form is deferred to a separate design task.

### CLI and lifecycle

- Required commands are `install <release>`, `list`/`ls`, `releases`, `set`/`use`, `flutter ...`, `dart ...`, `sdk-path [<release>]`, `setup`, `doctor [--full] [--json]`, `remove <release>`, `repair <release>`, `cleanup [--dry-run]`, and `upgrade-wren`.
- Use Dart's `args` package `CommandRunner` and `Command` APIs as the standard command dispatch and parsing model for Wren commands, including commands added later. Keep existing feature behavior and domain logic intact where practical while migrating the current CLI and adding commands.
- Define `WrenCommand` as the Wren command base over `args.Command`. Implement `WrenCommandRunner` as a composition wrapper around a private `args.CommandRunner`, exposing registration only for `WrenCommand`; this makes registering a plain package command through Wren's runner a compile-time error. The Wren runner owns shared command registration and consistent Wren error and exit-status handling. Commands share Wren verbosity, output/error reporting, and access to the application context through the Wren command base.
- Construct one `WrenContext` per CLI invocation. Give it an explicit, typed, named-getter API for shared values and services obtained from compile-time configuration or runtime state. Commands in that invocation use the same context. Lazy initialization policy is deferred until a demonstrated performance need exists.
- Wren accepts `--verbose` among its own command arguments. For SDK launch, Wren parses its options only before `flutter` or `dart`; every token after that command is forwarded unchanged, in order, including `--verbose` and `--`. With no trailing tokens, pass an empty argument list.
- Preserve Wren's own option-placement contract during command-runner migration: `--verbose` is recognized among arguments belonging to Wren commands, including before or after a Wren command name; for `flutter` and `dart`, Wren may parse options only before the SDK command name. The runner and SDK command adapters must maintain that boundary while using the shared command model.
- SDK executables start directly without a shell. Connect caller stdin/stdout/stderr, preserve child exit status, and report `128 + signal` for signal termination. A process-start failure is Wren status `5`; a started process's numeric status is passed through.
- Wren statuses: `0` success; `1` doctor found critical issues after a complete diagnosis; `2` usage/syntax; `3` no usable release or detected prelaunch damage; `4` operation failure or incomplete doctor diagnosis; `5` SDK launch failure; `6` cancellation or unavailable required confirmation.
- `list` reports installed releases and known readiness. `install` on a healthy installed release is a no-op; on a damaged release it directs to repair. A release detected as damaged stays registered as needing repair. Wren does not silently substitute another release for a selected damaged release.
- `repair <release>` validates fully and reports healthy without downloading when it already has trusted expected contents for every present group. Its first validation of an optional group fetched through a direct SDK path may fetch that group's source even when the local files are sound. A private-file repair waits for Wren-launched users and, for externally recorded releases, asks the user to close editors and confirm. Source-only repair changes no live path and needs no editor confirmation. Failed/interrupted repair publishes nothing.
- `sdk-path` prints only the fixed real SDK root. Without a release argument it resolves the active release, including environment exact override; with an argument it targets that release. A successful call persistently records external use. Setup prints VS Code `dart.getFlutterSdkCommand` guidance and fixed-path JetBrains guidance, including workspace/reload considerations, without editing shell or editor configuration.
- Wren provides `WREN_FLUTTER_RELEASE` for shims and SDK launches and `--release <release>` before an SDK command for direct invocation. `--release` takes precedence. Shims preserve SDK argument forwarding and process leases.
- Forwarded `flutter upgrade` and `flutter channel` remain transparent, but modifying a Wren-managed checkout in place is unsupported. Later validation detects changed framework/cache identity and marks damage.
- Removal may target active releases. It waits for Wren-launched use leases, makes the release unavailable before deletion, clears a matching global fallback, does not edit the pubspec, and reports resulting selection. If deletion fails after becoming unavailable, status `4` is returned and a later remove finishes cleanup. Successful removal reclaims private files and newly unreferenced shared artifact sources. If it was the final release, ask before deleting the shared Git repository; declining or noninteractive use retains that repository and removal succeeds.
- If a release has been exposed by `sdk-path`, private-file repair or removal requires close-editor confirmation. Declining or missing noninteractive confirmation returns `6`; source-only repair does not require it. Successful repair preserves the record; successful removal clears it. Wren does not claim to detect direct editor processes.
- `cleanup --dry-run` previews candidates. Ordinary cleanup removes only provable crash-orphan stages and unreferenced shared artifact sources, requires no second confirmation, reports reclaimed items, and preserves the shared Git repository and Wren rollback binary.
- Lock and use-lease waits are visible. Ctrl-C cancels only the waiting command with status `6`; the lock/lease holder continues.

### Distribution and Wren self-upgrade

- `upgrade-wren` considers published stable Wren releases only, selects the highest SemVer rather than trusting a chronological “latest” pointer, and upgrades only if newer than the running version. Equal/older is a no-op; no prerelease or downgrade.
- For a writable regular direct-install executable, download the exact host asset, verify SHA-256 and expected version, stage beside the current executable, and verify the staged executable runs before replacement. Keep one prior working binary, replace atomically, and restore it if post-replacement validation fails. A pre-replacement failure leaves the current executable untouched; the previous copy supports recovery after an interrupted later swap.
- Refuse to modify symlinked, unwritable, or otherwise unsuitable executables. Report manual replacement steps without requesting `sudo`. Self-upgrade never changes Flutter releases or their caches.

## Testing Decisions

- Tests should assert user-visible behavior at the highest practical seam: CLI invocation and observable filesystem/process outcomes. Avoid tests coupled to private helper structure.
- Exercise command-runner behavior, aliases, verbosity placement, usage errors, exit-status mapping, and context-backed command behavior through the CLI invocation seam. Assert observable behavior instead of testing base-class internals or context implementation details directly.
- Exercise command aliases, option parsing, exact argument preservation, exit statuses, stdin/stdout/stderr forwarding, and child signal/exit behavior through the CLI boundary.
- Exercise active-release selection against temporary current-directory pubspecs, stable and prerelease SemVer constraints, absent/malformed keys, global fallback, and exact override precedence.
- Exercise `set` by inspecting resulting YAML and fallback state, including absent keys, conflicting constraints, declined/noninteractive language-version confirmation, prerelease Dart normalization, and the 2.19.0 eligibility boundary.
- Exercise catalog eligibility, native host filtering, framework/engine identity, archive verification, Dart runtime validation, and atomic visibility with fixture catalogs and staged filesystem trees.
- Exercise concurrent install, joined shared downloads, lock cancellation, process leases, remove/repair waits, external-use confirmation, failed operations, retry-from-scratch, and cleanup dry-run using controlled child processes and temporary stores.
- Exercise source/private separation by mutating one release's live cache and confirming another release and retained source remain unchanged. Exercise damaged-source readiness propagation and automatic recovery of dependents with valid private files.
- Exercise optional artifact repair through the CLI and staged filesystem trees with per-supported-release-family fixtures. Cover never-used and already-present groups, a first-seen direct-editor group that needs one trusted source fetch, later healthy repair without a download, overlapping archive destinations, changed or deleted interior files, surviving stamps, missing or corrupt stamps with distinctive files, fully erased groups with and without Wren records, unavailable trusted sources, and staged restoration. Confirm external Gradle/Maven caches are untouched.
- Exercise setup-generated shims and `sdk-path` output/recording through their observable command behavior. Test GitHub release parsing and self-upgrade using a local/fake release source and replaceable executable fixture; cover bad checksums, unsuitable paths, interruption windows, and rollback.
- Exercise doctor's quick and full modes against healthy, damaged, and unverified releases; confirm safety-marker persistence without repair or downloads, offline behavior, setup and project findings, stalled-check continuation, exit precedence, verbose output, and one parseable versioned JSON report on stdout with progress on stderr.
- Existing repository prior art is only the default Dart CLI smoke test; feature tests will need to establish user-facing CLI and filesystem integration coverage before implementation is considered complete.
- For the command architecture, current prior art is the hand-written parser and thin executable entry point; retain the existing CLI invocation seam and expand its coverage rather than introducing a lower-level command-only test seam.

## Out of Scope

- Windows, Linux arm64, Intel macOS, and Rosetta-based Flutter installs.
- Installer scripts, package managers, automatic shell startup edits, or automatic editor configuration changes.
- Flutter releases with unknown bundled Dart metadata or canonical Dart versions below stable 2.19.0.
- Sharing live SDK files through symlinks or hardlinks; automatic promotion of first-use device/build-target downloads into shared sources.
- Repairing external Gradle/Maven caches outside Wren-managed SDK paths.
- Selecting by parent-directory pubspec discovery, writing a project pin, or silently switching away from a damaged selected release.
- Protect/unprotect editor commands or claims that Wren can detect all editor processes.
- Mutating a Wren-managed release in place via forwarded `flutter upgrade` or `flutter channel`.
- Wren prerelease self-upgrades, downgrades, or elevation-assisted self-upgrade.
- Targeted `wren doctor <release>` behavior until its separate design task is resolved.
- Lazy construction and memoization policy for `WrenContext` values or services until performance evidence justifies a decision.
- Replacing Wren's command model with a separate CLI framework or generated-command system.
- Redesigning command behavior beyond the command-runner migration and the contracts already recorded in this specification.
- Publishing implementation tickets to an external tracker; this specification and its decision sources are local project files.

## Further Notes

- Decision sources are the initiative map and its resolved tickets, including [Optional artifact repair guarantee after direct SDK use](issues/15-optional-artifact-repair-guarantee.md) and [Doctor](issues/16-doctor.md). [Optional artifact repair inventory](issues/14-optional-artifact-repair-inventory.md) supplies the technical evidence. The repository has no existing version-manager modules or architecture decisions; current product code is the default Dart starter. The glossary defines canonical terms and should be used in implementation and user-facing docs.
- The standalone [Wren doctor specification](../wren-doctor/spec.md) expands the agreed bare-command behavior and tests. The possible named-release form remains a separate design task.
- [Optional artifact repair inventory](issues/14-optional-artifact-repair-inventory.md) found that Flutter's stamps and path checks do not validate optional artifact contents, that archive destinations can overlap, and that `precache` cannot supply full atomic repair. [Optional artifact repair guarantee after direct SDK use](issues/15-optional-artifact-repair-guarantee.md) resolves the resulting conflict by permitting one trusted fetch for an already-evidenced first-seen group and retaining its validated contents for later checks. Every supported Flutter release family still needs version-aware artifact footprints and postprocessing before its repair implementation is accepted. Do not report stamp-only checks as full repair. [Research and targeted check](research/optional-artifact-repair-inventory.md).
- The current starter test is not meaningful prior art for the version manager; use the observable CLI/filesystem seams described above.
