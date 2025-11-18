import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Custom logger for the application
/// Provides different log levels and formatting based on environment
class AppLogger {
  static final Logger _logger = Logger(
    printer: SimplePrinter(printTime: true),
    filter: _CustomLogFilter(),
  );

  /// Log debug message
  static void debug(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Log info message
  static void info(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log warning message
  static void warning(
    dynamic message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log error message
  static void error(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Log fatal/critical message
  static void fatal(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);
  }
}

/// Custom log filter to control what gets logged in different environments
class _CustomLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    // In release mode, only log warnings and above
    if (kReleaseMode) {
      return event.level.value >= Level.warning.value;
    }
    // In debug mode, log everything
    return true;
  }
}
