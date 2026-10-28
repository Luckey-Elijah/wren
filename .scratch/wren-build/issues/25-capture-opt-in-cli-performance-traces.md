# 25: Capture opt-in CLI performance traces

Status: complete
Blocked by: [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren CLI performance tracing spec](../../wren-performance-tracing/spec.md), [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

Wren users can explicitly capture identifiable, local performance traces for CLI invocations, including startup, named Wren operations, and SDK child-process runtime, to observe performance over time.

## Acceptance criteria

- [x] `--trace` enables tracing and creates a unique JSONL file under Wren's per-user data directory; `--trace=<path>` appends to the selected path, resolving relative paths from the current working directory.
- [x] The global trace option is parsed by Wren before its command and is never forwarded to Flutter or Dart.
- [x] Without an explicit trace option, Wren creates no trace file, emits no trace records, and collects no tracing timings.
- [x] Each traced invocation writes a run summary and named operation span records as one JSON object per line, with a unique run ID on every record.
- [x] Run and span records include the agreed timestamps, elapsed durations, command/host/version metadata, parent operation relationships, results, and final exit status; arbitrary command arguments and environment values are omitted.
- [x] Startup and dispatch are included; Wren-managed I/O and wait operations use named spans; Flutter and Dart are measured only as child-process wall time.
- [x] Trace data remains local. Wren does not upload traces or include them in network requests.
- [x] If the trace destination cannot be opened, Wren reports the error, returns operation-failure status, and does not execute the requested command.
- [x] CLI tests exercise these behaviors through `runWren`, including default and explicit paths, append behavior, disabled behavior, failures, and child-process timing.
