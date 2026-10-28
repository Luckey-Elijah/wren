Type: grilling
Status: resolved
Blocked by: 01

## Question

Given that `wren set <release>` updates `pubspec.yaml`'s `environment` field, which keys and constraint forms should it write for the selected Flutter release and bundled Dart version? Specify how to handle a changed Dart lower bound (which changes language version), absent fields, conflicting existing constraints, and exact selection without a project pin.

## Answer

`wren set <release>` operates on `pubspec.yaml` in the current directory. It rewrites only `environment.flutter` and `environment.sdk` keys that already exist. Each rewritten key becomes a caret constraint starting at the selected Flutter release or its bundled Dart version, respectively (for example, `flutter: ^3.22.2` and `sdk: ^3.4.3`). It does not add missing keys or create a pubspec. Without a pubspec, ordinary `set` fails with a clear message.

Selecting a release authorizes Wren to replace an existing constraint that excludes it. Wren reports the overwritten constraints. If the rewrite changes the Dart SDK lower bound's major or minor version, Wren shows the proposed change and asks for confirmation before writing; declining leaves both the pubspec and global fallback untouched. A patch-only lower-bound change or another constraint conflict does not require a prompt. The noninteractive prompt behavior belongs to [CLI and execution contract](06-cli-and-execution-contract.md).

`wren set -g <release>` performs the same pubspec edit when a pubspec exists and also sets the global fallback. It may set the global fallback when the current directory has no pubspec.

`set` does not write a project pin. After the edit, Wren uses the already-decided active-release resolution rule, so a different installed release can be active immediately, and a newer compatible release can become active later. Wren reports the actual active release after `set`, including when only one constraint key exists. A prerelease selection writes a caret constraint containing that release's prerelease version in any existing Flutter key; prerelease eligibility remains governed by [Active release resolution](01-active-release-resolution.md).
