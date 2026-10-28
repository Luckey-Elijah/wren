# Wren

Wren manages Flutter releases and the Dart SDK bundled with each release. Install a release once, then run Flutter and Dart commands through Wren. In a project, Wren can select an installed release that matches the Flutter and Dart constraints in `pubspec.yaml`.

Wren supports Linux x86_64 and macOS on Apple Silicon.

## Install a release

Wren release archives contain a standalone native executable, so a separate
Dart SDK is not required. Download the archive for Linux x86_64 or Apple
Silicon macOS from the project's GitHub Releases, verify its SHA-256 checksum,
and follow the included [manual installation guide](packaging/INSTALL.md).
Wren requires system Git to install Flutter releases. The initial unsigned
macOS executable may require one-time approval in Privacy & Security settings.

## Get a project running

```sh
wren releases
wren releases 3.27.4
wren install 3.27.4
cd path/to/your_flutter_project
wren set 3.27.4
wren flutter pub get
```

Replace `3.27.4` with a version shown by `wren releases`. The version-specific query shows the bundled Dart version. Run `wren set` from a project directory whose `pubspec.yaml` has both `environment.flutter` and `environment.sdk` entries. Wren updates those entries to constraints for the installed Flutter release and its bundled Dart SDK.

`set` does not create a `pubspec.yaml` or add missing environment keys. If either key is missing, add it to the project's `environment` section before running `wren set`. Wren asks before changing the Dart major or minor lower bound because that can change the project's Dart language version.

To choose a release for projects that do not have matching constraints, set a global fallback:

```sh
wren set -g 3.27.4
```

This also updates existing Flutter and Dart environment keys in the current project's `pubspec.yaml`. Run it outside a project to set only the global fallback.

## Run Flutter and Dart

Pass Flutter or Dart arguments after the Wren command:

```sh
wren flutter test
wren flutter build ios
wren dart --version
```

Wren selects a release for each command. It checks these sources in order:

1. `--release <version>` before `flutter` or `dart`.
2. The `WREN_FLUTTER_RELEASE` environment variable.
3. The current directory's `pubspec.yaml` constraints.
4. The global fallback set with `wren set -g`.

For project selection, Wren chooses the newest installed release that satisfies both `environment.flutter` and `environment.sdk`. Wren checks only the `pubspec.yaml` in the current directory. A beta release is eligible only when the project constraints explicitly allow its prerelease version. If no installed release matches, Wren uses the global fallback. An exact selection with `--release` or `WREN_FLUTTER_RELEASE` takes precedence and does not fall back if that release is unavailable.

Automatic selection does not edit project or Wren configuration. Use `wren set` to update project constraints, and use `wren set -g` to update the global fallback.

Choose an exact release for one command or for a shell session:

```sh
wren --release 3.27.4 flutter test
WREN_FLUTTER_RELEASE=3.27.4 wren flutter test
```

## Common commands

| Command | What it does |
| --- | --- |
| `wren releases` | Lists eligible stable and beta Flutter releases for this machine. |
| `wren releases <version>` | Checks whether a release can be installed on this machine and shows its bundled Dart version. |
| `wren install <version>` | Downloads and installs an eligible Flutter release. |
| `wren list` or `wren ls` | Lists installed releases and whether each is ready to use. |
| `wren doctor` | Quickly checks installed releases, project compatibility, and the effective release selection. |
| `wren set <version>` or `wren use <version>` | Updates existing Flutter and Dart constraints in the current project's `pubspec.yaml`. |
| `wren set -g <version>` | Also sets the global fallback. |
| `wren flutter ...` or `wren dart ...` | Runs a command with the selected release and forwards its output and exit status. |
| `wren sdk-path [<version>]` | Prints the fixed SDK directory for the active or named release. |
| `wren setup` | Creates optional `flutter` and `dart` PATH shims and prints shell and editor setup steps. |
| `wren repair <version>` | Checks or restores the retained shared engine source used by a release. |
| `wren remove <version>` | Removes an installed release. |
| `wren cleanup --dry-run` | Previews abandoned install stages and unused shared sources that cleanup can remove. |
| `wren cleanup` | Removes those abandoned stages and unused shared sources. |
| `wren upgrade-wren` | Installs the newest stable Wren executable and keeps the previous binary for rollback. |

## What Wren changes on your system

Wren keeps its Flutter checkouts, installed releases, downloaded sources, settings, and optional shims in its data directory. The default is `$XDG_DATA_HOME/wren` when `XDG_DATA_HOME` is set, or `~/.local/share/wren` otherwise. Set `WREN_DATA_DIR` to choose another location.

Installing a release contacts the Flutter release catalog, uses system Git to fetch Flutter source, and downloads the release's required SDK artifacts. Wren validates an installation before it becomes available. A failed or interrupted install does not appear as a ready release. Wren retains validated shared engine sources when installed releases use them, while each release keeps its own live SDK files and mutable cache.

Removing a release deletes its checkout and private SDK files. Wren also deletes shared engine sources when no installed release or active operation uses them. If you remove the last release, Wren asks before deleting the shared Flutter Git repository. A path exposed by `wren sdk-path` requires confirmation before removal.

Flutter commands may download optional platform or build artifacts into the selected release's private SDK cache. Flutter and Dart commands may also write the files they normally create in your project or package caches. Wren forwards those commands and does not control their project-file changes.

Wren's configuration and integration writes are:

- `wren set` rewrites existing `environment.flutter` and `environment.sdk` values in the current `pubspec.yaml`. It does not add keys or write a release pin.
- `wren set -g` writes the global fallback to `config.json` in Wren's data directory. `wren remove` clears that fallback if it points to the removed release. Removal does not edit `pubspec.yaml`.
- `wren setup` writes `bin/flutter` and `bin/dart` shims under Wren's data directory. It prints a PATH command for you to add to your shell. It does not edit shell startup files or editor settings.
- `wren sdk-path` prints an installed SDK's fixed directory and records that an external tool may use it. Wren asks for confirmation before removing that release later.
- `wren upgrade-wren` updates a suitable direct Wren installation to the newest stable release and retains the prior executable as `wren.previous` in Wren's data directory.
- Wren does not write trace logs by default. Add `--trace` before a Wren command to write a JSON Lines trace under `traces/` in Wren's data directory. Use `--trace=/path/to/file` to choose another trace file.

## Run Wren from source

To run Wren from this checkout, prefix each command with `dart run bin/wren.dart`. This requires Dart 3.13.4 or newer. To install a published standalone executable, follow the instructions above.

The `wren setup` PATH shims expect Wren to run as its own executable. Listing eligible releases and installing Flutter releases require network access. Installing Flutter releases also requires system Git.

## Verify this checkout

Run `tool/verify.sh` to check Dart formatting, analysis, and tests. To use a specific Dart SDK, set `DART_BIN` to its executable path.
