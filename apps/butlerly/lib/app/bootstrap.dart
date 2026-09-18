import 'dart:async';

import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/app/session/butlerly_session_guard.dart';
import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/core/analysis/bundled_analysis_rules.dart';
import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/restore_recovery_state.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/features/foundation/presentation/butlerly_launch_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

@visibleForTesting
final class ButlerlyStorageUnavailableException implements Exception {
  const ButlerlyStorageUnavailableException([this.cause]);

  final Object? cause;
}

@visibleForTesting
final class ButlerlyStartupFailure implements Exception {
  const ButlerlyStartupFailure({
    required this.code,
    required this.phase,
    required this.cause,
  });

  final String code;
  final String phase;
  final Object cause;

  @override
  String toString() => 'ButlerlyStartupFailure($code, $phase)';
}

@visibleForTesting
ButlerlyStartupFailure classifyStartupFailure(String phase, Object error) {
  if (error is ButlerlyStartupFailure) return error;

  if (error is ButlerlyStorageUnavailableException) {
    return ButlerlyStartupFailure(
      code: 'DB-UNAVAILABLE',
      phase: phase,
      cause: error,
    );
  }

  if (phase == 'database initialization') {
    if (error is RepositoryException) {
      final code = switch (error.code) {
        RepositoryFailureCode.unavailable => 'DB-UNAVAILABLE',
        RepositoryFailureCode.busy => 'DB-BUSY',
        RepositoryFailureCode.permission => 'DB-PERMISSION',
        RepositoryFailureCode.storageFull => 'DB-STORAGE-FULL',
        RepositoryFailureCode.constraint => 'DB-CONSTRAINT',
        RepositoryFailureCode.notFound => 'DB-NOT-FOUND',
        RepositoryFailureCode.migration => 'DB-MIGRATION',
        RepositoryFailureCode.integrity => 'DB-INTEGRITY',
        RepositoryFailureCode.unknown => 'DB-UNKNOWN',
      };
      return ButlerlyStartupFailure(code: code, phase: phase, cause: error);
    }
    return ButlerlyStartupFailure(code: 'DB-ERROR', phase: phase, cause: error);
  }

  final code = switch (phase) {
    'locale initialization' => 'INIT-LOCALE',
    'dependency configuration' => 'INIT-DI',
    'restore recovery initialization' => 'RECOVERY-STATE',
    'interrupted restore recovery' => 'RECOVERY-RESTORE',
    'private artifact cleanup' => 'MAINTENANCE-CLEANUP',
    'analysis rule installation' => 'ANALYSIS-RULES',
    _ => 'STARTUP-UNKNOWN',
  };
  return ButlerlyStartupFailure(code: code, phase: phase, cause: error);
}

@visibleForTesting
String startupDiagnosticCode(Object error) {
  if (error is ButlerlyStartupFailure) return error.code;
  if (error is ButlerlyStorageUnavailableException) return 'DB-UNAVAILABLE';
  if (error is RepositoryException) {
    return switch (error.code) {
      RepositoryFailureCode.unavailable => 'DB-UNAVAILABLE',
      RepositoryFailureCode.busy => 'DB-BUSY',
      RepositoryFailureCode.permission => 'DB-PERMISSION',
      RepositoryFailureCode.storageFull => 'DB-STORAGE-FULL',
      RepositoryFailureCode.constraint => 'DB-CONSTRAINT',
      RepositoryFailureCode.notFound => 'DB-NOT-FOUND',
      RepositoryFailureCode.migration => 'DB-MIGRATION',
      RepositoryFailureCode.integrity => 'DB-INTEGRITY',
      RepositoryFailureCode.unknown => 'DB-UNKNOWN',
    };
  }
  return 'STARTUP-UNKNOWN';
}

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final logger = AppLogger();
  logger.initialize();
  installErrorHandlers(logger);

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
    this.minimumLaunchDuration = ButlerlySessionConfig.launchDuration,
    this.launchElapsedNow,
    this.readyBuilder,
    this.onReady,
    super.key,
  });

  final AppLogger logger;
  final Future<void> Function() initialize;
  final Duration minimumLaunchDuration;
  final ButlerlyElapsedNow? launchElapsedNow;
  final WidgetBuilder? readyBuilder;
  final VoidCallback? onReady;

  @override
  State<ButlerlyStartupGate> createState() => _ButlerlyStartupGateState();
}

class _ButlerlyStartupGateState extends State<ButlerlyStartupGate>
    with WidgetsBindingObserver {
  Object? _failure;
  bool _ready = false;
  int _attempt = 0;

  Timer? _launchTimer;
  Stopwatch? _ownedLaunchClock;
  late ButlerlyElapsedNow _launchElapsedNow;
  Completer<void>? _launchCompleter;
  Duration _launchRemaining = Duration.zero;
  Duration? _launchStartedAt;
  late bool _foreground;

  @override
  void initState() {
    super.initState();
    _installLaunchClock(widget.launchElapsedNow);
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _foreground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _beginAttempt();
  }

  void _installLaunchClock(ButlerlyElapsedNow? injected) {
    _ownedLaunchClock?.stop();
    _ownedLaunchClock = null;
    if (injected != null) {
      _launchElapsedNow = injected;
      return;
    }
    final stopwatch = Stopwatch()..start();
    _ownedLaunchClock = stopwatch;
    _launchElapsedNow = () => stopwatch.elapsed;
  }

  void _beginAttempt() {
    final attempt = ++_attempt;
    final launchWindow = _beginLaunchWindow();
    unawaited(_runAttempt(attempt, launchWindow));
  }

  Future<void> _runAttempt(int attempt, Future<void> launchWindow) async {
    try {
      await Future<void>.sync(widget.initialize);
      await launchWindow;
      if (!mounted || attempt != _attempt) return;
      (widget.onReady ?? _completeColdLaunch)();
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _failure = null;
        _ready = true;
      });
    } catch (error, stackTrace) {
      _cancelLaunchWindow(complete: true);
      widget.logger.severe(
        'Butlerly startup initialization failed',
        error,
        stackTrace,
      );
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _failure = error;
        _ready = false;
      });
    }
  }

  Future<void> _beginLaunchWindow() {
    _cancelLaunchWindow(complete: true);
    final completer = Completer<void>();
    _launchCompleter = completer;
    _launchRemaining = widget.minimumLaunchDuration;
    _launchStartedAt = null;
    if (_launchRemaining <= Duration.zero) {
      completer.complete();
    } else if (_foreground) {
      _startLaunchCountdown();
    }
    return completer.future;
  }

  void _startLaunchCountdown() {
    final completer = _launchCompleter;
    if (!_foreground ||
        completer == null ||
        completer.isCompleted ||
        _launchRemaining <= Duration.zero) {
      return;
    }
    _launchTimer?.cancel();
    _launchStartedAt = _launchElapsedNow();
    _launchTimer = Timer(_launchRemaining, _completeLaunchWindow);
  }

  void _pauseLaunchCountdown() {
    _launchTimer?.cancel();
    _launchTimer = null;
    final startedAt = _launchStartedAt;
    _launchStartedAt = null;
    if (startedAt == null) return;
    final rawElapsed = _launchElapsedNow() - startedAt;
    final elapsed = rawElapsed.isNegative ? Duration.zero : rawElapsed;
    if (elapsed <= Duration.zero) return;
    _launchRemaining = elapsed >= _launchRemaining
        ? Duration.zero
        : _launchRemaining - elapsed;
  }

  void _completeLaunchWindow() {
    _launchTimer?.cancel();
    _launchTimer = null;
    _launchStartedAt = null;
    _launchRemaining = Duration.zero;
    final completer = _launchCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void _cancelLaunchWindow({required bool complete}) {
    _launchTimer?.cancel();
    _launchTimer = null;
    _launchStartedAt = null;
    final completer = _launchCompleter;
    if (complete && completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _launchCompleter = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_foreground) return;
        _foreground = true;
        if (_launchRemaining <= Duration.zero) {
          _completeLaunchWindow();
        } else {
          _startLaunchCountdown();
        }
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (!_foreground) return;
        _foreground = false;
        _pauseLaunchCountdown();
        return;
    }
  }

  void _completeColdLaunch() {
    if (appRouter.routeInformationProvider.value.uri.path == '/launch') {
      appRouter.go('/');
    }
  }

  void _retry() {
    setState(() {
      _failure = null;
      _ready = false;
    });
    _beginAttempt();
  }

  @override
  void dispose() {
    _attempt += 1;
    _cancelLaunchWindow(complete: true);
    _ownedLaunchClock?.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return widget.readyBuilder?.call(context) ?? const ButlerlyApp();
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _failure == null
          ? const ButlerlyLaunchSurface(
              screenKey: ValueKey('butlerly-startup-screen'),
              footer: SizedBox(
                key: ValueKey('butlerly-startup-progress'),
                width: 24,
                height: 24,
                child: CircularProgressIndicator(),
              ),
            )
          : _StartupFailureBody(error: _failure!, onRetry: _retry),
    );
  }
}

class _StartupFailureBody extends StatelessWidget {
  const _StartupFailureBody({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final diagnosticCode = startupDiagnosticCode(error);
    final storageUnavailable = diagnosticCode == 'DB-UNAVAILABLE';
    return Scaffold(
      key: const ValueKey('butlerly-startup-screen'),
      body: SafeArea(
        child: ButlerlyResponsiveBody(
          contentKey: const ValueKey('butlerly-startup-failure-content'),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 48),
                  const SizedBox(height: 20),
                  Text(
                    context.l10n.text(
                      storageUnavailable
                          ? 'localStorageUnavailable'
                          : 'pageUnavailable',
                    ),
                    key: const ValueKey('butlerly-startup-error'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.text('dataPreserved'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Diagnostic: $diagnosticCode',
                    key: const ValueKey('butlerly-startup-diagnostic'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const ValueKey('butlerly-startup-retry'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(context.l10n.text('tryAgain')),
                  ),
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
    await initializeLocalDatabaseForStartup(database, logger);
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
      try {
        await recoverInterruptedLocalRestore(
          database,
          services<LocalDataManager>(),
          recoveryState: recoveryState,
        );
      } catch (error, stack) {
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

    if (services.isRegistered<FinanceServices>() &&
        !(recoveryState?.isRecoveryRequired ?? false)) {
      phase = 'analysis rule installation';
      logger.info('Startup: installing bundled analysis rules');
      try {
        final installer = services<FinanceServices>().installBuiltInRules;
        final installation = installer == null
            ? null
            : await installBundledAnalysisRules(installer);
        if (installation != null && installation.diagnostics.isNotEmpty) {
          logger.warning(
            'Some bundled analysis rules were rejected: '
            '${installation.diagnostics.length}',
          );
        }
        logger.info('Startup: bundled analysis rules ready');
      } catch (error, stackTrace) {
        logger.severe(
          'Bundled analysis rule installation failed; continuing',
          error,
          stackTrace,
        );
      }
    }

    logger.info('Startup: application ready');
  } catch (error, stackTrace) {
    final failure = classifyStartupFailure(phase, error);
    logger.severe(
      'Startup failed during $phase [${failure.code}]',
      error,
      stackTrace,
    );

    try {
      await services.reset(dispose: false);
    } catch (_) {}
    try {
      await database?.close();
    } catch (_) {}

    Error.throwWithStackTrace(failure, stackTrace);
  }
}

@visibleForTesting
Future<void> initializeLocalDatabaseForStartup(
  LocalDatabase database,
  AppLogger logger,
) async {
  try {
    await database.initialize();
    if (database.status != DatabaseStatus.ready) {
      throw const ButlerlyStorageUnavailableException();
    }
  } on RepositoryException catch (error, stackTrace) {
    switch (error.code) {
      case RepositoryFailureCode.unavailable:
      case RepositoryFailureCode.busy:
      case RepositoryFailureCode.permission:
      case RepositoryFailureCode.storageFull:
        database.status = DatabaseStatus.unavailable;
        logger.severe(
          'Local storage is unavailable during startup',
          error,
          stackTrace,
        );
        throw ButlerlyStorageUnavailableException(error);
      case RepositoryFailureCode.constraint:
      case RepositoryFailureCode.notFound:
      case RepositoryFailureCode.migration:
      case RepositoryFailureCode.integrity:
      case RepositoryFailureCode.unknown:
        rethrow;
    }
  }
}

@visibleForTesting
void installErrorHandlers(AppLogger logger) {
  FlutterError.onError = (details) {
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
