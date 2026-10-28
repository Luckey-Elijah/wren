# 01: Migrate existing Wren CLI commands to the typed args architecture

**What to build:** Wren contributors and users get a Dart-native CLI structure for the commands already implemented. Existing command behavior remains intact, while the shared architecture makes future command additions consistent and enforces Wren command registration at compile time.

**Blocked by:** [02: Install a stable Flutter release on Linux](../../wren-build/issues/02-install-stable-flutter-linux.md)

**Status:** ready-for-agent

- [ ] Use Dart's `args` package `CommandRunner` and `Command` APIs for the Wren command tree.
- [ ] Migrate every Wren command implemented by the start of this ticket, including `releases` and `install`, while preserving the CLI behavior specified for those commands.
- [ ] Add `WrenCommand` and a `WrenCommandRunner` composition wrapper. Keep the package runner private and expose command registration that accepts only `WrenCommand`, so registering a plain package `Command` through the Wren runner fails at compile time.
- [ ] Give `WrenCommand` shared Wren verbosity, output/error handling, status handling, and access to one `WrenContext` constructed per CLI invocation.
- [ ] Give `WrenContext` explicit typed getters for the shared compile-time configuration and runtime values and services used during that invocation. Defer lazy-initialization policy.
- [ ] Preserve the option-placement contract: `--verbose` is recognized among Wren-owned command arguments, while for `flutter` and `dart` Wren options are parsed only before the SDK command and every following token remains an unchanged SDK argument.
- [ ] Update project agent guidance to require future CLI work to follow the version-manager spec and use `WrenCommand`, `WrenCommandRunner`, and `WrenContext`.
- [ ] Verify existing command behavior through the CLI invocation seam, including verbosity placement, help and usage errors, exit statuses, and fixture-backed release/install behavior. Do not couple tests to base-class internals.
