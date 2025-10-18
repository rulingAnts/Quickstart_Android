import 'package:flutter/foundation.dart';

/// Tiny logging helper that is safe for production (no prints) and
/// concise for development. Uses debugPrint to avoid console flooding.
class Log {
  static void d(String message) {
    if (kDebugMode) debugPrint('[DEBUG] $message');
  }

  static void i(String message) {
    debugPrint('[INFO] $message');
  }

  static void w(String message, [Object? error, StackTrace? stackTrace]) {
    final suffix = _formatSuffix(error, stackTrace);
    debugPrint('[WARN] $message$suffix');
  }

  static void e(String message, [Object? error, StackTrace? stackTrace]) {
    final suffix = _formatSuffix(error, stackTrace);
    debugPrint('[ERROR] $message$suffix');
  }

  static String _formatSuffix(Object? error, StackTrace? stackTrace) {
    final parts = <String>[];
    if (error != null) parts.add(error.toString());
    if (stackTrace != null) parts.add('\n$stackTrace');
    return parts.isEmpty ? '' : ' :: ${parts.join(' :: ')}';
  }
}
