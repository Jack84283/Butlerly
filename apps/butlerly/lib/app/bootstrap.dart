import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    initializeDateFormatting('en'),
    initializeDateFormatting('es'),
    initializeDateFormatting('zh'),
  ]);

  final logger = AppLogger();
  logger.initialize();
  _installErrorHandlers(logger);

  final database = LocalDatabase(logger: logger);
  await database.initialize();

  configureDependencies(
    configuration: const AppConfiguration(),
    database: database,
    logger: logger,
  );

  if (services.isRegistered<FinanceServices>()) {
    final sources = <String, String>{};
    for (final path in _analysisRulePaths) {
      sources[path] = await rootBundle.loadString(path);
    }
    final catalog = await rootBundle.loadString(
      'assets/analysis_rules/catalog.yaml',
    );
    final installation = await services<FinanceServices>().installBuiltInRules
        ?.call(sources, catalogSource: catalog);
    if (installation != null && installation.diagnostics.isNotEmpty) {
      logger.warning(
        'Some bundled analysis rules were rejected: '
        '${installation.diagnostics.length}',
      );
    }
  }

  runApp(const ProviderScope(child: ButlerlyApp()));
}

const _analysisRulePaths = [
  'assets/analysis_rules/metrics/ANL-R001.yaml',
  'assets/analysis_rules/metrics/ANL-R002.yaml',
  'assets/analysis_rules/metrics/ANL-R003.yaml',
  'assets/analysis_rules/metrics/ANL-R004.yaml',
  'assets/analysis_rules/metrics/ANL-R010.yaml',
  'assets/analysis_rules/metrics/ANL-R016.yaml',
  'assets/analysis_rules/insights/ANL-R014.yaml',
  'assets/analysis_rules/insights/ANL-R020.yaml',
  'assets/analysis_rules/data_quality/ANL-R090.yaml',
  'assets/analysis_rules/data_quality/ANL-R091.yaml',
  'assets/analysis_rules/data_quality/ANL-R092.yaml',
];

void _installErrorHandlers(AppLogger logger) {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logger.severe(
      'Uncaught Flutter framework error',
      details.exception,
      details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    logger.severe('Uncaught platform error', error, stack);
    return true;
  };
}
