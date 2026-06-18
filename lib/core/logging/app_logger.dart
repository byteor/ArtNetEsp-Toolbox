import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

enum LogLevel { debug, info, warning, error }

class LogEntry {
  const LogEntry(this.time, this.level, this.tag, this.message);

  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  String get timeLabel {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.${three(time.millisecond)}';
  }
}

/// Lightweight app logger: keeps a bounded in-memory ring buffer (so screens can
/// show recent activity) and exposes a broadcast [stream]. Also forwards to
/// `dart:developer` so messages appear in the IDE/console.
///
/// Debug-level messages are only recorded when [debugEnabled] is true (driven by
/// the Settings "Debug logging" toggle).
class AppLogger {
  AppLogger({int capacity = 500}) : _capacity = capacity;

  final int _capacity;
  final ListQueue<LogEntry> _buffer = ListQueue<LogEntry>();
  final StreamController<LogEntry> _controller =
      StreamController<LogEntry>.broadcast();

  bool debugEnabled = false;

  Stream<LogEntry> get stream => _controller.stream;
  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_buffer);

  void debug(String tag, String message) {
    if (debugEnabled) _add(LogLevel.debug, tag, message);
  }

  void info(String tag, String message) => _add(LogLevel.info, tag, message);

  void warning(String tag, String message) =>
      _add(LogLevel.warning, tag, message);

  void error(String tag, String message, [Object? error]) =>
      _add(LogLevel.error, tag, error == null ? message : '$message: $error');

  void _add(LogLevel level, String tag, String message) {
    final entry = LogEntry(DateTime.now(), level, tag, message);
    _buffer.addLast(entry);
    while (_buffer.length > _capacity) {
      _buffer.removeFirst();
    }
    if (!_controller.isClosed) _controller.add(entry);
    developer.log(message, name: tag, level: _developerLevel(level));
  }

  static int _developerLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
    }
  }

  void clear() => _buffer.clear();

  void dispose() {
    if (!_controller.isClosed) _controller.close();
  }
}
