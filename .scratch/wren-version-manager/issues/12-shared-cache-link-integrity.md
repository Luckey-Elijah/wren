Type: research
Status: resolved
Blocked by: 05, 09

## Question

Can Wren safely share immutable engine and bundled Dart artifacts between installed Flutter releases while ordinary Flutter bootstrap, `precache`, updater commands, and direct editor use can write under each checkout's `bin/cache`? Using first-party Flutter source and, where source alone is inconclusive, a small targeted experiment on the supported host layout, identify which entries can be linked to a shared engine-commit cache, how those links must be laid out so Flutter cannot mutate another release's shared target, and which cheap readiness and full repair checks detect link drift or corruption. State any entries that need private per-release copies and the remaining tradeoff for a product decision.

## Context

[Install and cache model](05-install-and-cache-model.md) chooses shared immutable engine/Dart entries. [External SDK integration](09-external-sdk-integration.md) supports direct editor use and records externally used SDK paths, which protects against Wren reclamation but not SDK-initiated writes. Flutter's [bootstrap](https://raw.githubusercontent.com/flutter/flutter/master/bin/internal/shared.sh), [Dart updater](https://raw.githubusercontent.com/flutter/flutter/master/bin/internal/update_dart_sdk.sh), and [artifact cache updater](https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter_tools/lib/src/cache.dart) may change cache paths. This research should establish the safe boundary before the specification treats those entries as immutable.

## Answer

[Full findings, sources, and the targeted Linux experiment](../research/shared-cache-link-integrity.md). Flutter 3.7.0 and a recent release both extract engine archives into `bin/cache/artifacts/engine/<directory>` during cache refresh. `flutter precache --force` can trigger that path even when a checkout's stamps were initially correct. The Linux experiment confirmed that extraction through a directory symlink changed the shared target and another release's view. Linking an engine extraction directory, its ancestor, or the whole `bin/cache` is therefore unsafe for Wren's transparent Flutter and direct SDK use.

The inspected Dart updater moves a whole `bin/cache/dart-sdk` link aside before replacing it; the web SDK updater deletes a whole `bin/cache/flutter_web_sdk` link before refill. Those are possible narrow link candidates under the inspected Flutter commands, with their stamps and temporary paths private. Package leaf links detach on their own refill, but newer recursive postprocessing can follow sibling links, so package links are not proven safe. No live link can promise isolation from an editor or other direct user explicitly writing through the exposed SDK path. Engine directories, package materializations, bootstrap state, stamps, snapshots, downloads, and cache parent directories should remain per-release; a shared validated engine-commit payload can seed independent private files through copy-on-write cloning where supported and byte copying elsewhere.

Cheap readiness checks should verify the framework and engine identity, recorded cache inventory, allowed link type and exact target, required file presence and executability, and private stamp coherence. Full `repair` should walk the expected inventory, verify recorded file digests and types, confirm bundled Dart and host tools run, and stage replacements without changing a shared target in place while it has users. The remaining product choice is whether the disk saving from narrow Dart/web links justifies their direct-write caveat or whether all exposed artifacts must be independent. That choice is [Shared artifact reuse policy](13-shared-artifact-reuse-policy.md).
