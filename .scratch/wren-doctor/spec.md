# Wren doctor

## Problem Statement

Developers need to understand whether Wren itself is set up correctly, which Flutter releases are installed, whether those installations remain usable, and how each release relates to the current project's constraints. The planned list command checks readiness cheaply, while repair performs deeper validation and may change files. Neither gives a single, safe overview of the whole environment. A quick inspection must stay responsive, and a deeper inspection must not claim health when local evidence is insufficient.

## Solution

Add bare **wren doctor** as an offline diagnostic command. Its default mode quickly checks every installed release, Wren setup, current-project compatibility, and effective release selection. **wren doctor --full** validates the local integrity of every installed release more deeply. Both modes report clear next steps and distinguish installation integrity from compatibility and selection. **--verbose** expands check detail; **--json** emits one versioned report for tools. Doctor does not launch an SDK, download data, or repair files. When it confirms damage, it persists only the safety marker that prevents the damaged release from launching until repair.

## User Stories

1. As a Wren user, I want one command to summarize my environment, so that I can understand my installed releases and setup.
2. As a Wren user, I want the ordinary doctor command to finish promptly, so that I can get useful findings without waiting for a complete SDK scan.
3. As a Wren user, I want every installed release included in the ordinary report, so that damage in an inactive release is visible.
4. As a Wren user, I want quick release checks to agree with list and prelaunch checks, so that those commands do not give contradictory readiness signals.
5. As a Wren user, I want setup problems shown alongside release problems, so that I can find the actual cause of a failure.
6. As a Wren user, I want Wren's executable, registry, storage, fallback, and installed shims inspected, so that broken Wren-owned setup is identifiable.
7. As a Wren user, I want the current process's PATH inspected, so that I can see which optional shims are available to this invocation.
8. As a Wren user, I want absent optional shim paths reported without failing the diagnosis, so that choosing not to use shims is not treated as damage.
9. As a Wren user, I want missing system Git reported as a critical finding, so that I know why install and repair operations will fail.
10. As a Wren user, I want doctor to avoid claiming it verified permanent shell or editor settings, so that its report stays trustworthy.
11. As a project developer, I want doctor to inspect only a pubspec in the current directory, so that it follows Wren's ordinary project boundary.
12. As a project developer, I want compatibility reported for every installed release, so that I can see my available choices.
13. As a project developer, I want compatibility to reflect both the full Flutter range and the bundled Dart range, so that a plausible Flutter version is not mistakenly called compatible.
14. As a project developer, I want prerelease eligibility to follow normal Wren selection rules, so that beta releases are described consistently.
15. As a project developer, I want the effective release and its selection source reported, so that I can understand the effect of project constraints, exact overrides, and the global fallback.
16. As a project developer, I want an incompatible effective selection reported without failing doctor, so that I can inspect an intentional override or fallback.
17. As a Wren user, I want no selected release reported as an actionable finding without failing doctor, so that a fresh setup can still be diagnosed.
18. As a Wren user outside a project, I want compatibility marked not applicable, so that the absence of a pubspec is not mistaken for an error.
19. As a Wren user, I want an explicit full mode to validate every installed release's local files and metadata, so that I can seek stronger evidence of installation integrity.
20. As a Wren user, I want full validation to include the retained shared artifact source and release-private files, so that damage in either place is found.
21. As a Wren user, I want full validation to inspect optional SDK artifact groups evidenced as present, so that used platforms are covered without fetching never-used ones.
22. As a Wren user, I want an optional artifact without trusted local validation data reported as incomplete, so that stamps alone are never presented as proof of integrity.
23. As a Wren user, I want doctor to work offline and avoid launching Flutter or Dart, so that diagnosis does not download data or mutate SDK caches.
24. As a Wren user, I want confirmed damage marked as needing repair, so that a later SDK launch cannot ignore a fault doctor found.
25. As a Wren user, I want damage in a retained shared source reflected on its dependent installed releases, so that none is presented as safe to launch.
26. As a Wren user, I want doctor to leave SDK files unchanged and suggest repair, so that inspection never starts a replacement operation.
27. As a Wren user, I want a simple repair command as the next step, so that I need not interpret a speculative repair plan.
28. As a Wren user, I want a check that stalls to time out, so that doctor does not hang without explaining its state.
29. As a Wren user, I want an unverified or timed-out check labeled incomplete rather than damaged, so that uncertainty is not mistaken for corruption.
30. As a Wren user, I want the scan to continue after one incomplete release, so that I still receive findings for the others.
31. As a Wren user, I want progress during full validation, so that a long but advancing scan remains understandable.
32. As a Wren user, I want integrity described as basic checks passed, fully verified, needs repair, or incomplete, so that the report conveys the strength of its evidence.
33. As a Wren user, I want one summary line per release and actionable findings in the ordinary report, so that I can scan it quickly.
34. As a Wren user, I want verbose mode to show individual checks without changing scan depth, so that I can investigate a result without accidentally requesting a full scan.
35. As a script author, I want one versioned JSON report on stdout, so that I can parse findings without scraping human text.
36. As a script author, I want partial findings in JSON even when diagnosis fails, so that I can still inspect the successful checks.
37. As a script author, I want progress and verbose logs on stderr, so that JSON on stdout remains parseable.
38. As a script author, I want a completed scan with critical findings to exit 1, so that automation can detect confirmed problems.
39. As a script author, I want an incomplete scan to exit 4 even when it also found damage, so that automation knows the report does not cover everything.
40. As a script author, I want informational compatibility and selection findings to retain exit 0 when checks complete, so that expected project choices do not fail automation.
41. As a script author, I want usage errors to exit 2 and cancellation to exit 6, so that doctor fits Wren's existing CLI conventions.

## Implementation Decisions

- The command surface for this spec is bare **wren doctor**, optionally with **--full**, **--json**, and the existing global **--verbose** option. **--full** controls scan depth; **--verbose** controls detail. A release argument is not defined here.
- Quick mode scans all registered installed releases using the same cheap readiness criteria as list and prelaunch. Those checks include recorded identity, source readiness metadata, required files and executable modes, the cache boundary, and stamp coherence. Passing them means basic checks passed, not fully verified.
- Full mode scans all registered installed releases against the complete integrity criteria that repair can check using local evidence. It validates the release checkout, retained shared source, release-private host artifacts, and optional SDK artifact groups evidenced as present. It does not fetch a source or perform repair.
- Optional group presence follows the version-aware repair inventory: a current or stale group stamp, distinctive group-owned files, or a retained Wren inventory record is evidence. A shared parent directory alone is not. If a present group lacks trusted local expected contents, full doctor reports incomplete and points to repair, which may establish and retain that evidence.
- Doctor never accesses the network or launches Flutter or Dart. It may inspect local files and metadata. It persists only confirmed needs-repair safety state, including for releases dependent on a damaged retained shared source. Timeout, unavailable evidence, and other uncertainty do not become damage markers.
- Integrity, compatibility, and effective selection are separate report dimensions. Integrity uses basic checks passed, fully verified, needs repair, or incomplete. Compatibility uses the existing current-directory pubspec, full Flutter and bundled Dart constraints, and prerelease rules. Effective selection uses existing override, project, and global-fallback precedence and reports its source.
- Incompatible installed alternatives, an incompatible effective selection, no selected release, and absence of a current-directory project are informational. This diagnostic classification does not change SDK launch behavior.
- Setup validation covers Wren's executable, registry, storage, configured global fallback, installed shims, current-process PATH, and required system Git. Missing optional paths and settings outside Wren's control are information. Missing Git and confirmed broken Wren-owned configuration are critical findings. An uninspectable component is incomplete.
- Quick checks use short operation timeouts. Full scans may run longer while making progress, but stalled operations time out. Doctor continues checking other releases and retains partial findings. Progress is visible to a human. If a release has both confirmed damage and an unfinished check, retain both findings, persist only the proven damage marker, and treat the overall diagnosis as incomplete.
- The ordinary human report summarizes setup, each release, current-project compatibility, effective selection, and actionable next steps. Verbose mode adds check detail. JSON mode emits a single schema-versioned document on stdout, including partial findings and the check depth. Progress and logs go to stderr. The structured model keeps integrity, compatibility, selection and its source, setup findings, and completion distinct.
- Exit 0 means diagnosis completed with no critical findings. Exit 1 means completed diagnosis with at least one critical finding, including a release needing repair or missing Git. Exit 4 means diagnosis was incomplete because a check timed out or failed internally; it takes precedence over exit 1. Usage errors exit 2; cancellation exits 6. Doctor does not use no-usable-release exit 3 for informational selection findings or SDK-launch exit 5.
- A confirmed damaged release receives the next step **wren repair** for that release. Doctor need not predict whether repair will replace a shared source, checkout, or private artifact.

## Testing Decisions

- Use the highest practical seam: invoke the CLI against controlled temporary project directories and Wren stores, then assert stdout, stderr, exit status, and observable persisted safety markers. Avoid tests coupled to private checker classes or helper methods. One CLI plus filesystem seam covers the feature.
- Exercise quick mode with multiple installed releases, including healthy, damaged, inactive, and shared-source-dependent releases. Confirm that its readiness result matches list and prelaunch behavior and that it does not perform full hashing.
- Exercise full mode with valid required files, damaged checkouts, damaged shared sources, damaged private artifacts, optional groups with trusted local contents, and first-seen optional groups without trusted local contents.
- Confirm that only proven damage creates a persistent needs-repair marker, including dependent releases, and that incomplete checks do not. Assert no downloads, SDK launches, repairs, or other SDK file changes.
- Exercise current-directory pubspec discovery, absent pubspec, Flutter and Dart range compatibility, prerelease eligibility, exact overrides, global fallback, incompatible effective selection, and no selected release through the CLI report.
- Exercise setup findings for missing Git, broken Wren-owned configuration, absent optional shim paths, installed shims, and current-process PATH. Verify severity and exit behavior for each.
- Exercise short quick-check stalls, full-scan progress, per-check timeout, continuation to other releases, partial reports, and exit 4 precedence over exit 1.
- Parse JSON output from successful, critical, and incomplete runs. Confirm a single versioned document on stdout, structured dimensions, and progress or verbose detail only on stderr.
- Existing test prior art is only the starter CLI smoke test. The broader version-manager spec already chooses observable CLI and filesystem outcomes as its testing seam; doctor should extend that seam.

## Out of Scope

- Targeted **wren doctor <release>** behavior; it was deferred to a separate design task.
- Running Flutter or Dart as a health probe, contacting the release catalog, downloading artifacts, or automatically repairing files.
- Persistent shell startup or editor settings validation or modification. Doctor reports only the current process's PATH and Wren-owned shim state.
- A detailed prediction of repair steps. The actionable suggestion is the relevant repair command.
- Changing project constraints, the global fallback, release selection, or SDK launch policy.
- Defining the underlying install, repair, cache, and selection systems beyond the interfaces doctor consumes from the broader version-manager specification.

## Further Notes

- The repository is still a Dart CLI starter, so the doctor command and its version-manager dependencies do not yet exist. This is an implementation spec, not a description of shipped behavior.
- The accepted decision record is in the broader version-manager initiative's doctor decision. Its main specification defines the shared release, readiness, selection, and repair contracts.
- The optional-artifact repair guarantee permits repair to obtain trusted validation data for a first-seen present group and retain it for later offline checks. Until that data exists, full doctor must report incomplete rather than fully verified.
- The local repository guidance keeps this specification under the local scratch initiative. No external issue tracker or triage label is configured for this repository.
