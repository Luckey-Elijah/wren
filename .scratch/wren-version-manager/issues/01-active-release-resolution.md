Type: grilling
Status: resolved

## Question

Given that Wren automatically chooses the newest compatible installed release without writing a project pin, what is its exact active-release precedence across a project's `pubspec.yaml` environment and the global fallback? Define the search boundary for a project, prerelease eligibility, whether both Dart and Flutter constraints must match, and what Wren does when no installed release satisfies them.

## Answer

Wren checks for `pubspec.yaml` in the **current working directory only**. When present, it automatically selects the newest installed Flutter release that satisfies the full `environment.flutter` range and whose bundled Dart satisfies `environment.sdk`. It does not write a project pin. Installed beta releases participate in automatic selection only when the project constraints explicitly allow prereleases.

If that project has no compatible installed release, Wren uses the configured global fallback, even if that fallback does not satisfy the project's constraints. The global fallback also applies when the current directory has no `pubspec.yaml`. If no fallback is configured and no project release can be selected, the command's failure behavior is specified in [CLI and execution contract](06-cli-and-execution-contract.md).
