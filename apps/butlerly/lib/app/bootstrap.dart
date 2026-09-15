import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/restore_recovery_state.dart';
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

  final logger = AppLogger();
  logger.initialize();
  _installErrorHandlers(logger);

  // Paint a Flutter surface immediately. Startup used to await every local
  // initialization step before runApp(), which meant any first-run failure or
  // stall left iOS showing an unexplained blank window. The gate keeps startup
  // visible and recoverable while preserving the same initialization order.
  runApp(
    ProviderScope(
      child: ButlerlyStartupGate(
        logger: logger,
        initialize: () => initializeButlerly(logger),
      ),
    ),
  );
}

@visibleForTesting
class ButlerlyStartupGate extends StatefulWidget {
  const ButlerlyStartupGate({
    required this.logger,
    required this.initialize,
    super.key,
  });

  final AppLogger logger;
  final Future<void> Function() initialize;

  @override
  State<ButlerlyStartupGate> createState() => _ButlerlyStartupGateState();
}

class _ButlerlyStartupGateState extends State<ButlerlyStartupGate> {
  Object? _failure;
  bool _ready = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _beginAttempt();
  }

  void _beginAttempt() {
    final attempt = ++_attempt;
    Future<void>.sync(widget.initialize).then(
      (_) {
        if (!mounted || attempt != _attempt) return;
        setState(() {
          _failure = null;
          _ready = true;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        widget.logger.severe(
          'Butlerly startup initialization failed',
          error,
          stackTrace,
        );
        if (!mounted || attempt != _attempt) return;
        setState(() => _failure = error);
      },
    );
  }

  void _retry() {
    setState(() {
      _failure = null;
      _ready = false;
    });
    _beginAttempt();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const ButlerlyApp();

    const background = Color(0xFF0A0A0D);
    const primaryText = Color(0xFFF6F0E7);
    const secondaryText = Color(0xFFB8B2AA);
    const brand = Color(0xFF720018);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorSchemeSeed: brand,
      ),
      home: Scaffold(
        key: const ValueKey('butlerly-startup-screen'),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: brand,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Butlerly',
                      style: TextStyle(
                        color: primaryText,
                        fontSize: 32,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_failure == null) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      const Text(
                        'Preparing your local data…',
                        key: ValueKey('butlerly-startup-progress'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: secondaryText),
                      ),
                    ] else ...[
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFFFB4AB),
                        size: 32,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Butlerly couldn't initialize local storage.",
                        key: ValueKey('butlerly-startup-error'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your local data has not been erased. '
                        'You can try initialization again.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: secondaryText),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        key: const ValueKey('butlerly-startup-retry'),
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
Future<void> initializeButlerly(AppLogger logger) async {
  LocalDatabase? database;
  var phase = 'locale initialization';

  try {
    logger.info('Startup: initializing locale data');
    await Future.wait([
      initializeDateFormatting('en'),
      initializeDateFormatting('es'),
      initializeDateFormatting('zh'),
    ]);

    phase = 'database initialization';
    logger.info('Startup: opening local database');
    database = LocalDatabase(logger: logger);
    await database.initialize();
    logger.info('Startup: local database ready');

    phase = 'dependency configuration';
    configureDependencies(
      configuration: const AppConfiguration(),
      database: database,
      logger: logger,
    );
    logger.info('Startup: dependencies configured');

    phase = 'restore recovery initialization';
    final recoveryState = services.isRegistered<RestoreRecoveryState>()
        ? services<RestoreRecoveryState>()
        : null;
    await recoveryState?.initialize();
    logger.info('Startup: restore recovery checked');

    if (database.status == DatabaseStatus.ready &&
        services.isRegistered<LocalDataManager>()) {
      phase = 'interrupted restore recovery';
      // Analyze durable restore intent before any retention cleanup. A crash can
      // leave the safety-backup reference only in restore-origin.json; pruning
      // history before reading that sidecar could delete the required recovery
      // snapshot.
      try {
        await recoverInterruptedLocalRestore(
          database,
          services<LocalDataManager>(),
          recoveryState: recoveryState,
        );
      } catch (error, stack) {
        // Recovery-state persistence deliberately closes the in-memory gate before
        // touching disk. If persistence then fails (for example under storage
        // pressure), continue into the recovery-only UI rather than aborting the
        // whole app. Any failure before that gate is established remains fatal.
        if (!(recoveryState?.isRecoveryRequired ?? false)) rethrow;
        logger.severe(
          'Restore recovery persistence failed after the recovery gate closed',
          error,
          stack,
        );
      }

      phase = 'private artifact cleanup';
      final backupManager = services.isRegistered<LocalBackupManager>()
          ? services<LocalBackupManager>()
          : null;
      final incident = recoveryState?.incident;
      final recoveryIsUnknown =
          incident != null && incident.safetyBackupPath.isEmpty;
      // Cleanup is housekeeping, not a prerequisite for reading the local
      // ledger. Preserve startup availability if it fails, while still keeping
      // restore recovery itself blocking when integrity cannot be established.
      if (!recoveryIsUnknown && backupManager != null) {
        try {
          await backupManager.cleanupOrphanedPrivateArtifacts();
          logger.info('Startup: private artifact cleanup complete');
        } catch (error, stackTrace) {
          logger.severe(
            'Startup maintenance cleanup failed; continuing',
            error,
            stackTrace,
          );
        }
      }
    }

    // A controlled-recovery incident means the database/evidence pair or runtime
    // refresh has not yet been proven safe. Do not perform normal startup writes.
    if (services.isRegistered<FinanceServices>() &&
        !(recoveryState?.isRecoveryRequired ?? false)) {
      phase = 'analysis rule installation';
      logger.info('Startup: installing bundled analysis rules');
      try {
        final sources = <String, String>{};
        for (final path in _analysisRulePaths) {
          sources[path] = await rootBundle.loadString(path);
        }
        final catalog = await rootBundle.loadString(
          'assets/analysis_rules/catalog.yaml',
        );
        final installation = await services<FinanceServices>()
            .installBuiltInRules
            ?.call(sources, catalogSource: catalog);
        if (installation != null && installation.diagnostics.isNotEmpty) {
          logger.warning(
            'Some bundled analysis rules were rejected: '
            '${installation.diagnostics.length}',
          );
        }
        logger.info('Startup: bundled analysis rules ready');
      } catch (error, stackTrace) {
        // Insights and analysis can report unavailable data later; they must not
        // make the core local ledger impossible to open.
        logger.severe(
          'Bundled analysis rule installation failed; continuing',
          error,
          stackTrace,
        );
      }
    }

    logger.info('Startup: application ready');
  } catch (error, stackTrace) {
    logger.severe('Startup failed during $phase', error, stackTrace);

    // A retry must begin from a clean runtime registration state, but never
    // delete user files or database contents. Close only the active handle and
    // clear dependency registrations created by the failed attempt.
    try {
      await services.reset(dispose: false);
    } catch (_) {}
    try {
      await database?.close();
    } catch (_) {}

    Error.throwWithStackTrace(error, stackTrace);
  }
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
  'assets/analysis_rules/insights/ANL-R021.yaml',
  'assets/analysis_rules/insights/ANL-R022.yaml',
  'assets/analysis_rules/insights/ANL-R023.yaml',
  'assets/analysis_rules/insights/ANL-R024.yaml',
  'assets/analysis_rules/insights/ANL-R025.yaml',
  'assets/analysis_rules/insights/ANL-R026.yaml',
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
