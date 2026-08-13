import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/app/theme/theme_mode_provider.dart';
import 'package:butlerly/features/foundation/presentation/first_use_preferences_page.dart';
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

    final firstUse = preference.value?.firstUseCompleted == false;

    return MaterialApp.router(
      title: 'Butlerly',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: locale,
      routerConfig: appRouter,
      builder: (context, child) {
        if (preference.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (firstUse) return const FirstUsePreferencesPage();
        return child ?? const SizedBox.shrink();
      },
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
