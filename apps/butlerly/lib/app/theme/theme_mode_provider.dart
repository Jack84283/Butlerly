import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stored appearance is independent of Flutter's three-value ThemeMode.
enum ButlerlyAppearance {
  system,
  light,
  navy,
  dark;

  static ButlerlyAppearance fromStored(String? value) =>
      ButlerlyAppearance.values.firstWhere(
        (appearance) => appearance.name == value,
        orElse: () => ButlerlyAppearance.system,
      );

  ThemeMode get themeMode => switch (this) {
    ButlerlyAppearance.system => ThemeMode.system,
    ButlerlyAppearance.light => ThemeMode.light,
    ButlerlyAppearance.navy || ButlerlyAppearance.dark => ThemeMode.dark,
  };

  Brightness resolveBrightness(Brightness platformBrightness) => switch (this) {
    ButlerlyAppearance.system => platformBrightness,
    ButlerlyAppearance.light => Brightness.light,
    ButlerlyAppearance.navy || ButlerlyAppearance.dark => Brightness.dark,
  };
}

final appearanceProvider = Provider<ButlerlyAppearance>((ref) {
  return ButlerlyAppearance.fromStored(
    ref.watch(userPreferenceProvider).value?.appearance,
  );
});

/// Keep existing ThemeMode consumers compatible.
final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(appearanceProvider).themeMode,
);
