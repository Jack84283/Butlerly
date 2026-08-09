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

  void info(String message) => _logger.info(redact(message));

  void warning(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.warning(redact(message));
  }

  void severe(String message, Object error, StackTrace? stackTrace) {
    _logger.severe(redact(message));
  }

  /// Removes common sensitive values before an application message is emitted.
  /// Errors are deliberately not forwarded because platform errors can include
  /// user-entered data or local paths.
  static String redact(String value) {
    return value
        .replaceAll(RegExp(r'\b\d{12,19}\b'), '[redacted-number]')
        .replaceAll(
          RegExp(r'\b\d+(?:\.\d{1,2})?\s?(?:USD|EUR|GBP|JPY)\b'),
          '[redacted-money]',
        )
        .replaceAll(
          RegExp(
            r'(amount|merchant|receipt|notes?)\s*[:=]\s*[^,\n]+',
            caseSensitive: false,
          ),
          r'$1=[redacted]',
        );
  }
}
