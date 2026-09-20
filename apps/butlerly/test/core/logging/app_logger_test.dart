import 'dart:async';
import 'dart:io';

import 'package:butlerly/app/bootstrap.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  final logger = AppLogger()..initialize();
  late StreamSubscription<LogRecord> subscription;
  late List<LogRecord> records;
  late List<String> output;
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    records = [];
    output = [];
    subscription = Logger.root.onRecord.listen(records.add);
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) output.add(message);
    };
  });

  tearDown(() async {
    debugPrint = originalDebugPrint;
    await subscription.cancel();
  });

  test('exception payloads and traces never reach the log or console', () {
    const privatePath = '/Users/private/person/receipts/medical.pdf';
    final errors = <Object>[
      const FileSystemException('Jane Doe paid 123.45 CAD', privatePath),
      PlatformException(
        code: 'private-account',
        message: 'Jane Doe',
        details: privatePath,
      ),
      StateError('123.45 CAD'),
      _UnprintableException(),
    ];
    for (final error in errors) {
      logger.severe(
        'Local operation failed',
        error,
        StackTrace.fromString(privatePath),
      );
    }
    expect(records, hasLength(errors.length));
    for (var i = 0; i < errors.length; i++) {
      expect(
        records[i].message,
        'Local operation failed [${errors[i].runtimeType}]',
      );
      expect(records[i].error, isNull);
      expect(records[i].stackTrace, isNull);
    }
    expect(
      output,
      records.map((record) => 'SEVERE Butlerly: ${record.message}').toList(),
    );
  });

  test('framework and platform errors use only the privacy-safe logger', () {
    final oldFrameworkHandler = FlutterError.onError;
    final oldPlatformHandler = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = oldFrameworkHandler;
      PlatformDispatcher.instance.onError = oldPlatformHandler;
    });
    installErrorHandlers(logger);
    final error = _UnprintableException();
    final stack = StackTrace.fromString('/Users/private/financial-data.csv');
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
    expect(PlatformDispatcher.instance.onError!(error, stack), isTrue);
    expect(records, hasLength(2));
    expect(output, [
      'SEVERE Butlerly: Uncaught Flutter framework error [_UnprintableException]',
      'SEVERE Butlerly: Uncaught platform error [_UnprintableException]',
    ]);
  });

  test('redacts financial values and user-entered fields from log messages', () {
    final message = AppLogger.redact(
      'merchant: Corner Cafe, amount: 42.50 USD, receipt=IMG_1234.jpg, card 4242424242424242',
    );

    expect(message, isNot(contains('Corner Cafe')));
    expect(message, isNot(contains('42.50')));
    expect(message, isNot(contains('IMG_1234')));
    expect(message, isNot(contains('4242424242424242')));
    expect(message, contains('[redacted]'));
  });
}

class _UnprintableException implements Exception {
  @override
  String toString() => throw StateError('Exception text must not be inspected');
}
