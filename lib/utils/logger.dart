import 'package:flutter/foundation.dart'; // Add this import

class GameLogger {
  static void log(String message, {String level = 'INFO'}) {
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('$timestamp [$level] $message');
  }

  // You can add more specific log methods if needed
  static void debug(String message) => log(message, level: 'DEBUG');
  static void info(String message) => log(message, level: 'INFO');
  static void warning(String message) => log(message, level: 'WARNING');
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    log(message, level: 'ERROR');
    if (error != null) {
      log('Error Details: $error', level: 'ERROR');
    }
    if (stackTrace != null) {
      log('Stack Trace: $stackTrace', level: 'ERROR');
    }
  }
}