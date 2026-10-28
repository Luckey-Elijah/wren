# Wren CLI performance tracing

## Problem Statement

Wren users cannot currently tell how long a command takes, how much time Wren spends starting and preparing it, or which Wren-managed operations account for the time. Without consistent records, a user cannot identify a slow run or compare runs to notice a performance regression over time.

The user wants to collect performance data for Wren's offline-capable commands and startup work. The immediate goal is to capture identifiable, diagnosable runs. The user is not asking Wren to judge whether a run is slow or to fix performance problems.

## Solution

Add opt-in performance tracing to Wren invocations. A Wren user enables tracing with `--trace` or selects a destination with `--trace=<path>`. Tracing records startup, command duration, and named Wren-managed operation timings as JSON Lines in a local file. No trace data is uploaded.

Each trace has a run identifier that correlates its summary and operation records. A new default trace file is created for each traced invocation. An explicitly selected file is appended to, allowing multiple invocations to be compared in one file. Tracing is disabled by default and does not add trace records, initialize a trace writer, or capture timing data unless enabled (or a future feature explicitly opts in).

## User Stories

1. As a Wren user, I want to enable performance tracing for one invocation, so that ordinary invocations remain free of trace-file output.
2. As a Wren user, I want to choose a trace destination on the command line, so that I can keep related runs together or save a trace where I need it.
3. As a Wren user, I want a unique default trace file for each invocation, so that a new run never erases earlier evidence.
4. As a Wren user, I want the default trace filename to include a sortable UTC timestamp, so that I can find and compare runs in chronological order.
5. As a Wren user, I want concurrent default trace files to have collision-safe names, so that simultaneous commands do not overwrite each other's traces.
6. As a Wren user, I want a selected trace file to append new records, so that I can collect a history in one file without losing previous runs.
7. As a Wren user, I want the trace file to use JSON Lines, so that people, command-line tools, and agents can read the same data format.
8. As a Wren user, I want each invocation to have a unique run ID, so that I can group its records even when several runs append to the same file concurrently.
9. As a Wren user, I want a run summary to include the Wren version, host platform, command name, start time, total elapsed time, and exit status, so that I can compare runs and understand their outcomes.
10. As a Wren user, I want the trace to show startup and command-dispatch time, so that work before the command body is visible.
11. As a Wren user, I want named spans around Wren-managed operations, so that I can locate expensive work such as file access, catalog access, downloads, extraction, release selection, locks, and process waits.
12. As a Wren user, I want spans to show parent-child relationships, so that I can understand which operations contribute to a larger command phase.
13. As a Wren user, I want operation records to include start time, elapsed duration, and result, so that I can identify slow operations and see whether they succeeded.
14. As a Wren user, I want failed commands and failed operations represented in the trace, so that a run remains diagnosable when it does not complete successfully.
15. As a Wren user, I want SDK commands to record the total time Wren waits for the child process, so that a slow Flutter or Dart launch is distinguishable from Wren's own preparation time.
16. As a Wren user, I want trace records to omit arbitrary command arguments and environment values by default, so that secrets are not copied into trace files unintentionally.
17. As a Wren user, I want tracing to remain local even when a traced command performs network I/O, so that enabling traces never uploads performance data.
18. As a Wren user, I want Wren to report a trace-file open error and stop before running the requested command, so that a traced command is not mistaken for a captured run when no file can be created.
19. As a Wren contributor, I want tracing to share one invocation context and the existing CLI command model, so that timings remain consistent across commands.
20. As a Wren contributor, I want to verify tracing through the public CLI invocation seam, so that tests validate captured behavior rather than private tracing internals.

## Implementation Decisions

- Implement tracing as a Wren-wide CLI option, `--trace` or `--trace=<path>`, before the command name. The option belongs to Wren and must not be forwarded to Flutter or Dart.
- With `--trace` and no path, create a new file in Wren's per-user data directory under a trace-specific subdirectory. Name the file `wren-<UTC timestamp>-<unique suffix>.jsonl`; use a sortable timestamp with millisecond precision. The suffix prevents filename collisions.
- With `--trace=<path>`, use the supplied path as written. Resolve a relative path from the current working directory, create missing parent directories when possible, and append records. The file contents remain JSON Lines regardless of the supplied extension.
- If Wren cannot open the trace destination, report the error and stop before executing the requested command, returning the existing operation-failure status. Do not run an untraced command after the user explicitly requested a trace.
- Emit exactly one JSON object per line. Use a single versioned record format with a record kind distinguishing a run summary from a completed operation span. Include a unique invocation `runId` on every record. The run summary includes Wren version, host platform, Wren command name, UTC start time, total elapsed duration, and final exit status. A span includes its name, parent span identity where applicable, UTC start time, elapsed duration, and success or failure result.
- Use a monotonic clock for elapsed durations and UTC timestamps for record start times and filenames. The overall run duration begins at Wren's earliest measurable CLI entry point when tracing is enabled and ends after the command result is known. It does not claim to measure operating-system process creation or startup before Wren code begins.
- Instrument Wren-owned work with named spans, including relevant filesystem and configuration operations, release selection, catalog requests, downloads, archive extraction, lock or lease waits, and SDK child-process launch and wait. Capture command startup and dispatch as part of the run timeline.
- For `wren flutter` and `wren dart`, record the total child-process runtime and exit result. Do not attempt to instrument internal Flutter or Dart phases.
- Record operation failures and the final command status. Do not record arbitrary CLI argument values, environment values, file contents, or SDK output in the trace.
- When `--trace` is absent, do not create trace files, initialize a trace writer, emit trace records, or collect timing data for tracing. Ordinary argument parsing may recognize the flag; no performance trace is produced by default.
- Keep trace files local. Wren does not upload traces or include trace contents in network requests.
- Do not add automatic regression thresholds, anomaly classification, trace comparison commands, alerts, dashboards, or performance fixes in this initiative. The captured data is intended to support future analysis and informed decisions.
- Trace retention and automatic rotation are not defined by this initiative. Wren does not delete trace files as part of tracing.

## Testing Decisions

- Test through the existing `runWren` CLI invocation seam. Assert user-visible JSONL records, files, command results, standard output/error, and filesystem/process effects rather than private tracer classes or clock implementation details.
- When tracing is disabled, verify normal command behavior and output remain unchanged and no trace file is created.
- When tracing is enabled, invoke representative commands through `runWren` and parse every line as an independent JSON object. Verify run and span records, schema version, run ID correlation, required metadata, timestamps, elapsed durations, operation names, and final status.
- Verify a command failure and a failed operation are represented in the trace with their result and final status.
- Verify default filenames use the UTC timestamp convention, create distinct files for distinct invocations, and avoid collisions for concurrent or same-timestamp invocations.
- Verify an explicit path is resolved from the current directory when relative, parent directories are created, and new records append without damaging existing JSONL lines.
- Verify a trace destination that cannot be opened returns an operation failure and prevents the requested command from running. Use observable command or injected SDK-launch effects to prove it did not execute.
- Verify arbitrary command arguments and environment values are absent from trace contents.
- Verify `flutter` and `dart` child-process duration and status through the existing injected `SdkLauncher`, without coupling the test to tracing internals.
- Preserve the existing CLI invocation seam as the sole primary test seam. The repository already tests commands through `runWren`, temporary filesystem state, output sinks, and an injectable SDK launcher; use those patterns as prior art.

## Out of Scope

- Automatic detection, thresholding, or declaration of performance regressions.
- A report, comparison, dashboard, alert, or visualization interface for traces.
- Uploading trace data or integrating with a hosted observability service.
- Modifying Wren's commands to improve performance or changing command behavior to reduce measured duration.
- Instrumenting operating-system syscalls or internal Flutter and Dart execution phases.
- Recording arbitrary command arguments, environment values, file contents, or child-process output.
- Trace cleanup, retention limits, and automatic rotation.

## Further Notes

- The Wren version-manager specification already defers `WrenContext` lazy-initialization policy until performance evidence exists. This initiative adds a way to collect that evidence without deciding whether lazy initialization is needed.
- The current CLI architecture has `WrenCommand`, `WrenCommandRunner`, a single `WrenContext` per invocation, and `runWren` as the public test seam. The implementation ticket depends on the CLI architecture migration.
- The local Wren build-ticket directory is the issue tracker for this repository. This specification is kept in the local scratch initiative per repository guidance.
