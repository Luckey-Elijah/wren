import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// A callback that times an operation under a named span.
typedef TraceSpanRunner = Future<T> Function<T>(
  String name,
  Future<T> Function() operation,
);

/// Writes one invocation's local performance data as JSON Lines.
class TraceSession {
  // Named private constructors need the type name in Dart's syntax.
  // ignore: unnecessary_type_name_in_constructor
  TraceSession._(this._sink, this.path, this._startedAt, Stopwatch elapsed)
    : runId = _randomId(),
      _elapsed = elapsed;

  final IOSink _sink;
  final DateTime _startedAt;
  final Stopwatch _elapsed;
  final List<String> _parents = [];
  int _nextSpanId = 0;

  /// Unique identifier shared by records in this invocation.
  final String runId;

  /// Local trace destination.
  final String path;

  /// Opens [explicitPath] for append, or creates a unique default trace file.
  static Future<TraceSession> open({
    required String? explicitPath,
    required String dataDirectory,
    DateTime? startedAt,
    Stopwatch? elapsed,
  }) async {
    final file = explicitPath == null
        ? await _createDefaultFile(dataDirectory)
        : File(p.absolute(explicitPath));
    await file.parent.create(recursive: true);
    final check = await file.open(mode: FileMode.append);
    await check.close();
    final stopwatch = elapsed ?? (Stopwatch()..start());
    return TraceSession._(
      file.openWrite(mode: FileMode.append),
      file.path,
      startedAt ?? DateTime.now().toUtc(),
      stopwatch,
    );
  }

  /// Records startup work completed before command dispatch.
  Future<void> recordStartup(int durationMicros) => _write({
    'schemaVersion': 1,
    'recordType': 'span',
    'runId': runId,
    'spanId': 'span-${_nextSpanId++}',
    'name': 'cli.startup',
    'startedAt': _startedAt.toIso8601String(),
    'durationMicros': durationMicros,
    'result': 'success',
  });

  /// Times a named operation only while tracing is active.
  Future<T> span<T>(String name, Future<T> Function() operation) async {
    final id = 'span-${_nextSpanId++}';
    final parentId = _parents.isEmpty ? null : _parents.last;
    final startedAt = DateTime.now().toUtc();
    final elapsed = Stopwatch()..start();
    _parents.add(id);
    var result = 'success';
    try {
      final value = await operation();
      if (value is int && value != 0) result = 'failure';
      return value;
    } on Object {
      result = 'failure';
      rethrow;
    } finally {
      elapsed.stop();
      _parents.removeLast();
      await _write({
        'schemaVersion': 1,
        'recordType': 'span',
        'runId': runId,
        'spanId': id,
        ...?parentId == null ? null : {'parentSpanId': parentId},
        'name': name,
        'startedAt': startedAt.toIso8601String(),
        'durationMicros': elapsed.elapsedMicroseconds,
        'result': result,
      });
    }
  }

  /// Writes a final summary and closes the destination.
  Future<void> finish({
    required String command,
    required String? host,
    required String wrenVersion,
    required int exitStatus,
  }) async {
    _elapsed.stop();
    await _write({
      'schemaVersion': 1,
      'recordType': 'run',
      'runId': runId,
      'command': command,
      'host': host,
      'wrenVersion': wrenVersion,
      'startedAt': _startedAt.toIso8601String(),
      'durationMicros': _elapsed.elapsedMicroseconds,
      'exitStatus': exitStatus,
    });
    await _sink.flush();
    await _sink.close();
  }

  Future<void> _write(Map<String, Object?> record) async {
    _sink.writeln(jsonEncode(record));
    await _sink.flush();
  }

  static Future<File> _createDefaultFile(String dataDirectory) async {
    final directory = Directory(p.join(dataDirectory, 'traces'));
    await directory.create(recursive: true);
    while (true) {
      final timestamp = _timestamp(DateTime.now().toUtc());
      final file = File(
        p.join(directory.path, 'wren-$timestamp-${_randomId()}.jsonl'),
      );
      try {
        return await file.create(exclusive: true);
      } on FileSystemException {
        if (!file.existsSync()) rethrow;
      }
    }
  }

  static String _timestamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    String three(int number) => number.toString().padLeft(3, '0');
    return '${value.year}${two(value.month)}${two(value.day)}T'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}'
        '${three(value.millisecond)}Z';
  }

  static String _randomId() {
    final random = Random.secure();
    return '${random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')}'
        '${random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')}';
  }
}
