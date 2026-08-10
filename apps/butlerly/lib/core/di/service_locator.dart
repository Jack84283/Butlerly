import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:get_it/get_it.dart';

final services = GetIt.instance;

void configureDependencies({
  required AppConfiguration configuration,
  required LocalDatabase database,
  required AppLogger logger,
}) {
  services
    ..registerSingleton<AppConfiguration>(configuration)
    ..registerSingleton<AppLogger>(logger)
    ..registerSingleton<LocalDatabase>(database);

  if (database.status == DatabaseStatus.ready) {
    services.registerSingleton<FinanceServices>(
      FinanceServices(
        SqliteTransactionRepository(database.persistenceDatabase),
        SqlitePaymentSourceRepository(database.persistenceDatabase),
        SqliteMerchantRepository(database.persistenceDatabase),
        SqliteCategoryRepository(database.persistenceDatabase),
        SqliteTagRepository(database.persistenceDatabase),
        SqliteEvidenceRepository(database.persistenceDatabase),
      ),
    );
  }
}
