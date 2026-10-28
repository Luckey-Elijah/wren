Label: wayfinder:map

## Destination

A decision-ready specification for Wren's first usable Flutter and bundled Dart version manager: its CLI contract, project resolution, release/install model, caching, lifecycle, and distribution. The map ends when implementation can be planned without unresolved product or architecture choices.

## Notes

- Wren is currently the default Dart CLI starter; there is no version-manager functionality to preserve.
- Required commands: `install <release>` (including beta), `list`/`ls`, `releases`, `set [-g] <release>`/`use`, `flutter ...`, `dart ...`, `sdk-path [<release>]`, `setup`, `doctor` (with `--full` and `--json`), `remove <release>`, `repair <release>`, `cleanup` (with `--dry-run`), and `upgrade-wren`.
- Every Wren command supports `--verbose`. Everything after `wren flutter` or `wren dart` belongs to the invoked SDK executable, including flags and subcommands; Wren must not parse it as its own options.
- The first usable release targets macOS and Linux.
- Setup should be intuitive and mostly one-time; routine Flutter/Dart and editor use should not require users to manage Wren's lifecycle bookkeeping.
- Consult `grilling` and `domain-modeling` for human decisions. Research tickets consult `research`.
- Canonical terms are defined in [GLOSSARY.md](../../GLOSSARY.md).
- No issue-tracker configuration exists in this repo, so this effort uses the Wayfinder local Markdown tracker. Ticket state and dependencies live in `issues/`.

## Decisions so far

- [Active release resolution](issues/01-active-release-resolution.md): Check only the current directory, choose the newest fully compatible installed release, then use the global fallback; betas require an explicit prerelease constraint.
- [Set command and pubspec update](issues/02-set-and-pubspec.md): Rewrite only existing environment keys as caret ranges, confirm Dart language-version changes, and report the actual active release without a project pin.
- [Release catalog and compatibility](issues/03-release-catalog-and-compatibility.md): Flutter's host catalogs identify releases and usually bundled Dart; engine revisions come from the framework checkout, while separate engine integrity needs a policy.
- [Puro cache techniques](issues/04-puro-cache-techniques.md): Puro overlaps engine precaching with checkout and shares Git objects and engine artifacts by engine commit; Wren must choose its own concurrency and recovery rules.
- [Install and cache model](issues/05-install-and-cache-model.md): Use detached worktrees, a retained immutable engine artifact source with release-private files, parallel staged installs, and reference-safe reclamation.
- [CLI and execution contract](issues/06-cli-and-execution-contract.md): Preserve SDK arguments and exit status, fail without a selected release, and use distinct Wren statuses and conservative noninteractive prompt behavior.
- [Beta Dart version normalization](issues/10-beta-dart-version-normalization.md): Use the full prerelease build version for pubspec matching, `set`, and install validation; the catalog's leading base is display text.
- [Historical release constraints](issues/11-historical-release-constraints.md): Require known bundled Dart `>=2.19.0` for native-host releases; exclude older, prerelease-2.19, and unknown-Dart entries, so `set` keeps caret constraints.
- [Platforms and distribution](issues/07-platforms-and-distribution.md): Ship standalone direct downloads for the two tested hosts, require system Git, and self-upgrade stable Wren releases with a retained rollback binary.
- [Recovery and lifecycle](issues/08-recovery-and-lifecycle.md): Retry interrupted installs from scratch; repair private files and retained sources explicitly, wait for affected live users, and clean crash orphans only on request.
- [External SDK integration](issues/09-external-sdk-integration.md): Shims, fixed editor paths, and an exact CI override select releases; remembered external use gates changes to live SDK files without daily protection steps.
- [Shared cache integrity under Flutter writes](issues/12-shared-cache-link-integrity.md): Flutter refresh can write through shared engine-directory links; private materializations preserve release isolation, while narrow Dart/web links leave a direct-write tradeoff.
- [Shared artifact reuse policy](issues/13-shared-artifact-reuse-policy.md): Keep all live SDK artifacts private, retain one validated source per engine/host, and make source damage affect dependent release readiness until one repair restores healthy releases.
- [Optional artifact repair inventory](issues/14-optional-artifact-repair-inventory.md): Flutter's cache checks cannot validate optional artifact contents; first-seen editor downloads need a trusted manifest or a narrower repair guarantee.
- [Optional artifact repair guarantee after direct SDK use](issues/15-optional-artifact-repair-guarantee.md): Validate groups evidenced by stamps, distinctive files, or Wren records; permit one trusted fetch for first-seen groups, skip groups with no evidence, and leave external caches to their own tools.
- [Doctor](issues/16-doctor.md): Quick offline inspection covers all installed releases, setup, and current-project compatibility; `--full` validates local integrity, `--json` exposes structured findings, and only confirmed damage may persist a safety marker.

## Not yet specified

- The optional `doctor <release>` form is deferred to a separate design task.

## Out of scope

- Implementing and shipping the version manager; this map produces decisions for that work.
