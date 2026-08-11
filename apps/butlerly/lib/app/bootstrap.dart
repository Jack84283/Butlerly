import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/database/initial_master_data.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    final seeded = await services<FinanceServices>().seedInitialMasterData(
      buildInitialMasterData(),
    );
    if (seeded is ApplicationFailure<void>) {
      logger.warning('Initial local master data could not be prepared.');
    }
  }

  runApp(const ProviderScope(child: ButlerlyApp()));
}

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
