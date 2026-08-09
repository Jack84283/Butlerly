import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

class AppLogger {
  final Logger _logger = Logger('Butlerly');

  void initialize() {
    hierarchicalLoggingEnabled = true;
    Logger.root.level = kDebugMode ? Level.INFO : Level.WARNING;
    Logger.root.onRecord.listen((record) {
      debugPrint(
        '${record.level.name} ${record.loggerName}: ${record.message}',
      );
    });
  }

  void info(String message) => _logger.info(message);

  void warning(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.warning(message, error, stackTrace);
  }

  void severe(String message, Object error, StackTrace? stackTrace) {
    _logger.severe(message, error, stackTrace);
  }
}
