import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/app/session/butlerly_session_guard.dart';
import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/app/theme/theme_mode_provider.dart';
import 'package:butlerly/core/data/restore_recovery_state.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/features/foundation/presentation/first_use_preferences_page.dart';
import 'package:butlerly/features/foundation/presentation/restore_recovery_required_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ButlerlyApp extends ConsumerWidget {
  const ButlerlyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final preference = ref.watch(userPreferenceProvider);
    final colorTheme = ButlerlyColorTheme.values.firstWhere(
      (value) => value.name == (preference.value?.colorTheme ?? 'butlerRed'),
      orElse: () => ButlerlyColorTheme.butlerRed,
    );
    final recoveryState = services.isRegistered<RestoreRecoveryState>()
        ? services<RestoreRecoveryState>()
        : null;

    final firstUse = preference.value?.firstUseCompleted == false;

    return MaterialApp.router(
      title: 'Butlerly',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightFor(colorTheme),
      darkTheme: AppTheme.darkFor(colorTheme),
      themeMode: themeMode,
      locale: locale,
      routerConfig: appRouter,
      builder: (context, child) => ButlerlySessionGuard(
        router: appRouter,
        child: ListenableBuilder(
          listenable: appRouter.routeInformationProvider,
          builder: (context, _) {
            // A cold launch and an inactivity reset must show the branded
            // launch surface before first-use or restore-recovery overlays.
            if (appRouter.routeInformationProvider.value.uri.path ==
                '/launch') {
              return child ?? const SizedBox.shrink();
            }

            Widget normalContent() {
              if (preference.isLoading) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (firstUse) {
                return Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => const FirstUsePreferencesPage(),
                    ),
                  ],
                );
              }
              return child ?? const SizedBox.shrink();
            }

            if (recoveryState == null) return normalContent();
            return ListenableBuilder(
              listenable: recoveryState,
              builder: (context, _) {
                if (recoveryState.isRecoveryRequired) {
                  return const RestoreRecoveryRequiredPage();
                }
                return normalContent();
              },
            );
          },
        ),
      ),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
