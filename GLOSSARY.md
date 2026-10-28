# Wren version management

Wren manages locally installed Flutter releases and the Dart SDKs bundled with them.

## Language

**Flutter release**:
A published Flutter SDK version on a release channel, paired with its bundled Dart SDK.

**Wren release**:
A published version of the Wren command-line tool, independent of the Flutter releases it manages.

**Installed release**:
A Flutter release whose Wren installation has completed and remains registered locally. Damage found later can make it unavailable for launch until repair.

**Release needing repair**:
An installed release Wren will not launch because its required files or retained shared artifact source have been found missing or invalid. Repair must succeed before Wren launches it again.

**Release checkout**:
A Wren-managed Flutter framework working tree at the commit of one installed release.

**SDK path**:
The fixed Flutter SDK root directory of one installed release that Wren provides to an external tool.

**External SDK user**:
An editor or other tool that invokes a Wren-provided SDK path outside a Wren-launched process.

**Shared engine cache**:
Wren-managed immutable engine and bundled Dart artifacts used to prepare release-specific SDK caches. Installed releases use independent copies of those artifacts.

**Release-private artifact**:
A cached SDK artifact whose live files belong to one installed release; changing it does not change another release's artifact.

**Optional artifact group**:
A set of device or build-target SDK files a Flutter release acquires on demand. It may be absent from an installed release that has not used that target.

**PATH shim**:
A Wren-provided `flutter` or `dart` launcher that selects and runs an installed release from the user's command path.

**Project constraints**:
The current project's `pubspec.yaml` environment ranges for Flutter and Dart that Wren uses to find a compatible installed release.

**Active release**:
The installed release Wren selects for the current command, from an exact release selection, the current project's constraints, or the global fallback.

**Exact release selection**:
A caller's choice of one installed Flutter release for a command, overriding automatic project and global-fallback selection.

**Global fallback**:
The configured installed release Wren uses when project constraints do not select an installed release.
