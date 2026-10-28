Type: grilling
Status: resolved

## Question

Given that the first Wren release supports macOS and Linux, which architectures and installation channels must it cover, and what should `upgrade-wren` do for each distribution method? Decide how the Wren CLI bootstraps on machines without Dart installed, whether its shared-worktree install model requires a system Git executable or bundles one, and how self-upgrade preserves a working executable on failure.

## Answer

The first Wren release targets two machines the author can verify: Linux x86_64 on their Fedora 44 workstation and macOS arm64 on their Apple Silicon Mac. Wren ships a standalone native executable for each target, compiled from Dart with its runtime included. Running Wren does not require a separately installed Dart SDK. Wren uses the system Git executable for its shared Flutter repository and linked worktrees; it does not bundle Git. Git-dependent operations check for a usable Git and give actionable installation guidance when it is missing.

GitHub Releases is the canonical source for versioned Wren release archives for those two targets and a SHA-256 checksum manifest. Installation is by documented manual download and copy to a writable, regular executable on `PATH`; the first release has no installer script or package-manager channel. The initial Apple Silicon build may be unsigned for personal use, with any needed macOS approval step documented.

On each host, `wren releases` shows only Flutter releases with native host artifacts that Wren can install. An explicit `wren install` of a release without a matching native artifact fails with a clear host-availability explanation. Apple Silicon does not fall back to an Intel Flutter artifact through Rosetta.

`upgrade-wren` upgrades only the Wren CLI. It finds the highest-version published stable Wren release on GitHub, compares versions rather than relying on GitHub's chronological “latest” endpoint, and upgrades only if that version is newer than the running one. An equal or older stable release is an “already current” no-op; it neither selects prereleases nor downgrades. For a writable regular direct-install executable, Wren downloads the exact host asset, verifies its SHA-256 and expected version, and checks that the staged executable runs before replacing the current one. It stages beside the installed executable so the replacement can be atomic, retains one previous working binary, and restores it if validation after replacement fails. A failure or interruption before replacement leaves the current binary untouched; the previous binary remains available for recovery after an interruption later in the swap. An unwritable, symlinked, or otherwise unsuitable executable is not modified; Wren reports manual replacement steps without requesting `sudo`. This command does not change installed Flutter releases or their caches.

## Comments

First human decision round pending (2026-10-27): native host coverage (macOS/Linux × x64/arm64), initial installation channels, a standalone compiled Wren executable, and system versus bundled Git. The follow-on upgrade behavior depends on the selected channels.

First-round decisions (2026-10-27): cover only the author's current Linux machine (Fedora 44, x86_64, glibc 2.43) and Apple Silicon macOS, which the author can test. Ship direct downloads only, as standalone native executables requiring no installed Dart. Require system Git and report a useful preflight error when it is missing. Upgrade and distribution details remain under discussion.

Second-round decisions (2026-10-27): publish versioned release archives with manual installation instructions and no installer script. `upgrade-wren` considers only newer stable Wren CLI releases; an equal or older latest stable release is a no-op. The initial Apple Silicon build is for personal use and may be unsigned, with any necessary manual macOS approval step. The direct-upgrade and rollback contract remains under discussion.

Third human round pending (2026-10-27): whether GitHub Releases is the canonical archive/update source, and whether `upgrade-wren` self-replaces a direct-download executable using staged verification, an atomic swap, and a retained rollback copy.

Third-round decisions (2026-10-27): GitHub Releases is the canonical source for versioned Linux x86_64 and macOS arm64 Wren archives plus SHA-256 checksums. For a writable regular direct-install executable, `upgrade-wren` downloads a newer stable build, verifies checksum and version, keeps one previous executable, and atomically replaces it. A failed step must keep or restore the working executable and explain manual recovery; Wren never requests sudo or changes managed Flutter releases during its own upgrade.

Fourth human round pending (2026-10-27): whether Apple Silicon may run Intel-only Flutter releases through Rosetta, whether `releases` lists only native-installable artifacts or all releases with availability labels, and whether self-upgrade may follow a symlink to replace its target.

Fourth-round decisions (2026-10-27): only native arm64 Flutter host artifacts on Apple Silicon, with no Rosetta fallback. `releases` lists only Flutter releases with native host artifacts installable on the current machine; an explicit install of an unavailable release explains the mismatch. Direct self-upgrade refuses a symlinked Wren executable and provides manual replacement steps.

Consolidated decision reviewed with the human; final shared-understanding confirmation requested. The issue stays claimed until that confirmation arrives.

The human confirmed the consolidated decision on 2026-10-27. The answer above is the resolution.

Fact checks: [Dart's standalone executable](https://dart.dev/tools/dart-compile), [Flutter SDK archive](https://docs.flutter.dev/install/archive), [Flutter host prerequisites](https://docs.flutter.dev/install/manual), [Git linked worktrees](https://git-scm.com/docs/git-worktree), and [Homebrew's self-update policy](https://docs.brew.sh/Acceptable-Formulae).
