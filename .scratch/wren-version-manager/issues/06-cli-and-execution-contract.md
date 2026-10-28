Type: grilling
Status: resolved
Blocked by: 01

## Question

What is the exact command-line contract for aliases, `--verbose`, exit codes, prompts (including when neither a project release nor a global fallback exists), and launching `flutter`/`dart`? In particular, where may Wren parse its own options while guaranteeing every token after `wren flutter` or `wren dart` is forwarded verbatim to the selected SDK executable?

## Answer

`wren ls` is an exact alias of `wren list`, and `wren use` is an exact alias of `wren set`, including `-g`, prompts, output, and exit status.

Wren accepts `--verbose` anywhere among arguments to its own commands, including before or after the command name. For SDK launches, Wren may parse its options only before the `flutter` or `dart` command name: `wren --verbose flutter ...` enables Wren verbosity, while every token after `wren flutter` or `wren dart` belongs to the selected SDK executable. Wren forwards those tokens, including `--verbose`, other flags, subcommands, and `--`, unchanged and in order. An SDK launch with no trailing arguments passes an empty argument list to the executable.

If active-release resolution selects no installed release, `wren flutter` and `wren dart` fail immediately with a diagnostic and a suggested selection command. This holds even when releases are installed but none is selected, in both interactive and noninteractive use; there is no selection prompt. It supersedes the prompt clause in [Active release resolution](01-active-release-resolution.md).

Wren starts the selected SDK executable directly, without a shell, connects its stdin, stdout, and stderr to the caller, and returns the SDK's exit status unchanged (using the conventional `128 + signal` status when a signal terminates it). Wren holds the use lease decided in [Install and cache model](05-install-and-cache-model.md) until the SDK process exits. A failure to start the SDK is a Wren launch failure, not an SDK exit. Wren's own verbosity must not alter the child argument vector or replace its output.

Wren's documented statuses are `0` for its own successful commands, `2` for command syntax or usage errors, `3` when no usable release can be selected, `4` for a Wren operation failure, `5` for failure to launch the selected SDK, and `6` for cancellation or unavailable required confirmation. Once an SDK process starts, its exit status passes through even if its number matches a Wren status.

When `set` requires confirmation for a Dart language-version change, a decline or noninteractive input fails with status `6` before either pubspec or global fallback changes. When `remove` offers to delete the now-unused shared Git repository, declining retains it and still counts as a successful release removal. In noninteractive use, `remove` retains that optional repository, reports that it was kept, and succeeds if removal otherwise completed.

## Comments

Human decisions in progress:

- `ls` is an exact alias of `list`; `use` is an exact alias of `set`.
- Wren accepts `--verbose` anywhere among its own command arguments. For `wren dart` and `wren flutter`, every token after the SDK command name, including flags, belongs only to the SDK.
- If resolution selects no release, fail immediately and explain how to select one. This applies even when releases are installed and supersedes the prompt rule in [Active release resolution](01-active-release-resolution.md).
- SDK launches pass stdin, stdout, stderr, and the SDK exit status through transparently; Wren reports its own status for launch failures.
- Wren will document distinct exit codes for syntax errors, no usable release, and Wren operation/launch failures; the final numbers and cancellation behavior are in the answer above.
