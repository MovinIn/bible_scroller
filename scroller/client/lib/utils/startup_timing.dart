import 'package:flutter/foundation.dart';

/// Debug-only startup phase timing. Logs to console when [kDebugMode] is true.
class StartupTiming {
  StartupTiming._();

  static final Map<String, int> _starts = {};
  static final Map<String, int> _durations = {};

  static void start(String phase) {
    if (!kDebugMode) {
      return;
    }
    _starts[phase] = DateTime.now().millisecondsSinceEpoch;
  }

  static void end(String phase) {
    if (!kDebugMode) {
      return;
    }
    final started = _starts.remove(phase);
    if (started == null) {
      return;
    }
    final elapsed = DateTime.now().millisecondsSinceEpoch - started;
    _durations[phase] = elapsed;
    debugPrint('[startup] $phase: ${elapsed}ms');
  }

  static Future<T> track<T>(String phase, Future<T> Function() action) async {
    start(phase);
    try {
      return await action();
    } finally {
      end(phase);
    }
  }

  static void summary() {
    if (!kDebugMode || _durations.isEmpty) {
      return;
    }
    final total = _durations.values.fold<int>(0, (sum, ms) => sum + ms);
    debugPrint('[startup] summary (${total}ms total): $_durations');
  }
}
