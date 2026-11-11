import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/app/theme/theme_mode_provider.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stored identifiers retain the previous appearance choices', () {
    for (final appearance in ButlerlyAppearance.values) {
      expect(ButlerlyAppearance.fromStored(appearance.name), appearance);
    }
    expect(ButlerlyAppearance.fromStored(null), ButlerlyAppearance.system);
    expect(ButlerlyAppearance.fromStored('blue'), ButlerlyAppearance.system);
    expect(
      ButlerlyAppearance.fromStored('unsupported'),
      ButlerlyAppearance.system,
    );
  });

  test('System follows OS brightness, never selecting Navy', () {
    expect(ButlerlyAppearance.system.themeMode, ThemeMode.system);
    expect(ButlerlyAppearance.light.themeMode, ThemeMode.light);
    expect(ButlerlyAppearance.navy.themeMode, ThemeMode.dark);
    expect(ButlerlyAppearance.dark.themeMode, ThemeMode.dark);
    for (final brightness in Brightness.values) {
      expect(
        ButlerlyAppearance.system.resolveBrightness(brightness),
        brightness,
      );
      expect(
        ButlerlyAppearance.navy.resolveBrightness(brightness),
        Brightness.dark,
      );
    }
  });

  test('Light and Navy match FinIntel while Butlerly Dark is unchanged', () {
    final light = AppTheme.light.extension<ButlerlySemanticColors>()!;
    final navyTheme = AppTheme.navy;
    final navy = navyTheme.extension<ButlerlySemanticColors>()!;
    final dark = AppTheme.dark.extension<ButlerlySemanticColors>()!;
    expect(light.background, const Color(0xFFF2F3F7));
    expect(light.cardSurface, const Color(0xFFFFFFFF));
    expect(light.subtleSurface, const Color(0xFFEBEFF5));
    expect(light.overlaySurface, const Color(0xFFFFFFFF));
    expect(light.primaryText, const Color(0xFF151E2B));
    expect(light.secondaryText, const Color(0xFF516278));
    expect(light.controlPrimary, const Color(0xFF244D79));
    expect(light.secondaryActionSurface, const Color(0xFFE3EBF6));
    expect(light.border, const Color(0xFFD5DEE9));
    expect(light.inputBorder, const Color(0xFFA8BACD));
    expect(light.focusRing, const Color(0xFF225DA2));
    expect(navyTheme.brightness, Brightness.dark);
    expect(navy.background, const Color(0xFF0C1118));
    expect(navy.cardSurface, const Color(0xFF17212E));
    expect(navy.subtleSurface, const Color(0xFF101722));
    expect(navy.overlaySurface, const Color(0xFF202D3B));
    expect(navy.primaryText, const Color(0xFFE8EEF6));
    expect(navy.secondaryText, const Color(0xFFA5B4C7));
    expect(navy.controlPrimary, const Color(0xFF294767));
    expect(navyTheme.colorScheme.onPrimary, const Color(0xFFDBE9FF));
    expect(navy.secondaryActionSurface, const Color(0xFF202F46));
    expect(navy.border, const Color(0xFF2B394B));
    expect(navy.inputBorder, const Color(0xFF436B92));
    expect(navy.focusRing, const Color(0xFF8CC1FF));
    expect(dark.background, const Color(0xFF0D0D0D));
    expect(dark.cardSurface, const Color(0xFF181818));
    expect(dark.subtleSurface, const Color(0xFF222222));
    expect(dark.elevatedSurface, const Color(0xFF292B2D));
    expect(dark.primaryText, const Color(0xFFFFFFFF));
    expect(dark.secondaryText, const Color(0xFFB4B4B4));
    expect(dark.border, const Color(0xFF282C30));
  });

  test('text and buttons meet AA contrast for every accent and mode', () {
    for (final accent in ButlerlyColorTheme.values) {
      for (final theme in [
        AppTheme.lightFor(accent),
        AppTheme.navyFor(accent),
        AppTheme.darkFor(accent),
      ]) {
        final colors = theme.extension<ButlerlySemanticColors>()!;
        expect(
          _contrast(colors.primaryText, colors.cardSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(colors.secondaryText, colors.cardSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(
            theme.colorScheme.primary,
            theme.colorScheme.onPrimary,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(colors.primaryText, colors.secondaryActionSurface),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  test('saving an appearance updates providers without a restart', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(userPreferenceProvider.future);
    expect(container.read(appearanceProvider), ButlerlyAppearance.system);
    await container
        .read(userPreferenceProvider.notifier)
        .saveChanges(appearance: 'navy');
    expect(container.read(appearanceProvider), ButlerlyAppearance.navy);
    expect(container.read(themeModeProvider), ThemeMode.dark);
    await container
        .read(userPreferenceProvider.notifier)
        .saveChanges(appearance: 'dark');
    expect(container.read(appearanceProvider), ButlerlyAppearance.dark);
    await container
        .read(userPreferenceProvider.notifier)
        .saveChanges(appearance: 'light');
    expect(container.read(appearanceProvider), ButlerlyAppearance.light);
  });
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return ((a > b ? a : b) + 0.05) / ((a < b ? a : b) + 0.05);
}
