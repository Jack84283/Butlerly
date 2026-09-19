import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => services.reset());

  test('recovery contract remains available when SQLite cannot open', () {
    final logger = AppLogger();
    final database = LocalDatabase(logger: logger)
      ..status = DatabaseStatus.unavailable;
    configureDependencies(
      configuration: const AppConfiguration(),
      database: database,
      logger: logger,
    );
    expect(services.isRegistered<WorkspaceDataService>(), isTrue);
    expect(services<WorkspaceDataService>().hasRecoverySafetyCopy, isFalse);
  });
}
