import 'package:butlerly/app/shell/shared/primary_bottom_navigation.dart';
import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  group('Butler Red theme propagation', () {
    test('Light uses red for primary controls and focus', () {
      final theme = AppTheme.lightFor(ButlerlyColorTheme.butlerRed);
      final colors = theme.extension<ButlerlySemanticColors>()!;

      expect(colors.controlPrimary, const Color(0xFF7A1E3A));
      expect(colors.focusRing, const Color(0xFF7A1E3A));
      expect(colors.navigationSelectedIcon, const Color(0xFF7A1E3A));
      expect(theme.colorScheme.primary, colors.controlPrimary);
      expect(theme.colorScheme.secondary, colors.brand);
      expect(
        theme.scaffoldBackgroundColor,
        ButlerlySemanticColors.light.background,
      );
    });

    test('Navy uses red for primary, interactive and selected states', () {
      final theme = AppTheme.navyFor(ButlerlyColorTheme.butlerRed);
      final colors = theme.extension<ButlerlySemanticColors>()!;

      expect(colors.controlPrimary, const Color(0xFF813353));
      expect(colors.focusRing, const Color(0xFFCF7F9A));
      expect(colors.interactive, const Color(0xFFCF7F9A));
      expect(colors.navigationSelectedIcon, colors.interactive);
      expect(colors.interactiveStrong, const Color(0xFFD58DA5));
      expect(theme.colorScheme.primary, colors.controlPrimary);
      expect(theme.colorScheme.secondary, colors.brand);
      expect(
        theme.scaffoldBackgroundColor,
        ButlerlySemanticColors.navy.background,
      );
    });

    test('original Dark surfaces stay unchanged with the new red accents', () {
      final theme = AppTheme.darkFor(ButlerlyColorTheme.butlerRed);
      final colors = theme.extension<ButlerlySemanticColors>()!;

      expect(colors.background, ButlerlySemanticColors.dark.background);
      expect(colors.surface, ButlerlySemanticColors.dark.surface);
      expect(colors.controlPrimary, ButlerlySemanticColors.dark.controlPrimary);
      expect(colors.focusRing, const Color(0xFFCF7F9A));
      expect(colors.interactive, const Color(0xFFCF7F9A));
      expect(colors.navigationSelectedIcon, const Color(0xFFCF7F9A));
    });

    test('alternate accent palettes do not inherit Butler Red', () {
      final red = ButlerlySemanticColors.palette(
        Brightness.dark,
        ButlerlyColorTheme.butlerRed,
        navy: true,
      );
      final blue = ButlerlySemanticColors.palette(
        Brightness.dark,
        ButlerlyColorTheme.skyBlue,
        navy: true,
      );
      final green = ButlerlySemanticColors.palette(
        Brightness.dark,
        ButlerlyColorTheme.green,
        navy: true,
      );

      expect(blue.interactive, isNot(red.interactive));
      expect(green.interactive, isNot(red.interactive));
      expect(green.focusRing, const Color(0xFF8CC1FF));
      expect(blue.focusRing, const Color(0xFF8CC1FF));
    });
  });

  testWidgets(
    'device bottom navigation follows Butler Red appearance changes',
    (tester) async {
      Future<void> pumpDeviceNavigation(ThemeData theme) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: const SizedBox.shrink(),
              bottomNavigationBar: PrimaryBottomNavigation(
                navigationKey: const ValueKey('device-navigation'),
                destinations: const {
                  0: NavigationDestination(
                    icon: Icon(Icons.home),
                    label: 'Home',
                  ),
                  1: NavigationDestination(
                    icon: Icon(Icons.receipt_long),
                    label: 'Transactions',
                  ),
                },
                visualBranchIndexes: const [0, 1],
                currentIndex: 0,
                onSelected: (_) {},
              ),
            ),
          ),
        );
      }

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpDeviceNavigation(
        AppTheme.lightFor(ButlerlyColorTheme.butlerRed),
      );
      expect(find.byKey(const ValueKey('device-navigation')), findsOneWidget);
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.home))).color,
        const Color(0xFF7A1E3A),
      );

      await pumpDeviceNavigation(
        AppTheme.navyFor(ButlerlyColorTheme.butlerRed),
      );
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.home))).color,
        const Color(0xFFCF7F9A),
      );
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.receipt_long))).color,
        ButlerlySemanticColors.navy.tertiaryText,
      );
    },
  );
}
