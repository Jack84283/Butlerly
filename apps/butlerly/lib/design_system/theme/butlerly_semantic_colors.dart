import 'package:flutter/material.dart';

enum ButlerlyColorTheme { butlerRed, skyBlue, green }

@immutable
class ButlerlySemanticColors extends ThemeExtension<ButlerlySemanticColors> {
  const ButlerlySemanticColors({
    required this.background,
    required this.surface,
    required this.elevatedSurface,
    required this.subtleSurface,
    required this.primaryText,
    required this.secondaryText,
    required this.tertiaryText,
    required this.cardDivider,
    required this.border,
    required this.brand,
    required this.brandStrong,
    required this.interactive,
    required this.controlPrimary,
    required this.interactiveStrong,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.selection,
    required this.review,
  });

  final Color background;
  final Color surface;
  final Color elevatedSurface;
  final Color subtleSurface;
  final Color primaryText;
  final Color secondaryText;
  final Color tertiaryText;
  final Color cardDivider;
  final Color border;
  final Color brand;
  final Color brandStrong;
  final Color interactive;
  final Color controlPrimary;
  final Color interactiveStrong;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color selection;
  final Color review;

  /// Quiet-premium neutral foundation. Brand palettes only replace the accent
  /// roles so financial semantic colors remain stable and meaningful.
  static const dark = ButlerlySemanticColors(
    background: Color(0xFF0A0A0D),
    surface: Color(0xFF111114),
    elevatedSurface: Color(0xFF17171C),
    subtleSurface: Color(0xFF0F1013),
    primaryText: Color(0xFFF4F1EC),
    secondaryText: Color(0xFFB8B2AA),
    tertiaryText: Color(0xFF817C75),
    cardDivider: Color(0xFF25252B),
    border: Color(0xFF2F2F36),
    brand: Color(0xFF7A1E3A),
    brandStrong: Color(0xFF541127),
    interactive: Color(0xFFC76F8B),
    controlPrimary: Color(0xFF541127),
    interactiveStrong: Color(0xFF9A3655),
    success: Color(0xFF4DBA7A),
    warning: Color(0xFFD4A85B),
    error: Color(0xFFE16C72),
    info: Color(0xFF6DA7D8),
    selection: Color(0xFF24141A),
    review: Color(0xFFC76F8B),
  );

  static const light = ButlerlySemanticColors(
    background: Color(0xFFF7F5F1),
    surface: Color(0xFFFFFFFF),
    elevatedSurface: Color(0xFFFCFAF7),
    subtleSurface: Color(0xFFF1EEE8),
    primaryText: Color(0xFF19181A),
    secondaryText: Color(0xFF68635E),
    tertiaryText: Color(0xFF8A847D),
    cardDivider: Color(0xFFD9D4CE),
    border: Color(0xFFE2DDD7),
    brand: Color(0xFF7A1E3A),
    brandStrong: Color(0xFF541127),
    interactive: Color(0xFF7A1E3A),
    controlPrimary: Color(0xFF541127),
    interactiveStrong: Color(0xFF64162F),
    success: Color(0xFF287A52),
    warning: Color(0xFF916814),
    error: Color(0xFFB5444C),
    info: Color(0xFF356F9F),
    selection: Color(0xFFF0E2E6),
    review: Color(0xFF64162F),
  );

  static ButlerlySemanticColors palette(
    Brightness brightness,
    ButlerlyColorTheme theme,
  ) {
    final base = brightness == Brightness.dark ? dark : light;
    return switch (theme) {
      ButlerlyColorTheme.butlerRed => base,
      ButlerlyColorTheme.skyBlue => base.copyWith(
        brand: brightness == Brightness.dark
            ? const Color(0xFF315B82)
            : const Color(0xFF315B82),
        brandStrong: brightness == Brightness.dark
            ? const Color(0xFF1E3E5C)
            : const Color(0xFF234563),
        interactive: brightness == Brightness.dark
            ? const Color(0xFF7DB7E8)
            : const Color(0xFF315B82),
        controlPrimary: brightness == Brightness.dark
            ? const Color(0xFF1E3E5C)
            : const Color(0xFF234563),
        interactiveStrong: brightness == Brightness.dark
            ? const Color(0xFF4F82AF)
            : const Color(0xFF284E70),
        selection: brightness == Brightness.dark
            ? const Color(0xFF111F2B)
            : const Color(0xFFE2EAF1),
        review: brightness == Brightness.dark
            ? const Color(0xFF7DB7E8)
            : const Color(0xFF284E70),
      ),
      ButlerlyColorTheme.green => base.copyWith(
        brand: brightness == Brightness.dark
            ? const Color(0xFF246B57)
            : const Color(0xFF246B57),
        brandStrong: brightness == Brightness.dark
            ? const Color(0xFF16483B)
            : const Color(0xFF16483B),
        interactive: brightness == Brightness.dark
            ? const Color(0xFF66C7A0)
            : const Color(0xFF246B57),
        controlPrimary: brightness == Brightness.dark
            ? const Color(0xFF16483B)
            : const Color(0xFF16483B),
        interactiveStrong: brightness == Brightness.dark
            ? const Color(0xFF3B8E73)
            : const Color(0xFF1D5B4B),
        selection: brightness == Brightness.dark
            ? const Color(0xFF10251F)
            : const Color(0xFFE1EEE9),
        review: brightness == Brightness.dark
            ? const Color(0xFF66C7A0)
            : const Color(0xFF1D5B4B),
      ),
    };
  }

  @override
  ButlerlySemanticColors copyWith({
    Color? background,
    Color? surface,
    Color? elevatedSurface,
    Color? subtleSurface,
    Color? primaryText,
    Color? secondaryText,
    Color? tertiaryText,
    Color? cardDivider,
    Color? border,
    Color? brand,
    Color? brandStrong,
    Color? interactive,
    Color? controlPrimary,
    Color? interactiveStrong,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? selection,
    Color? review,
  }) => ButlerlySemanticColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    elevatedSurface: elevatedSurface ?? this.elevatedSurface,
    subtleSurface: subtleSurface ?? this.subtleSurface,
    primaryText: primaryText ?? this.primaryText,
    secondaryText: secondaryText ?? this.secondaryText,
    tertiaryText: tertiaryText ?? this.tertiaryText,
    cardDivider: cardDivider ?? this.cardDivider,
    border: border ?? this.border,
    brand: brand ?? this.brand,
    brandStrong: brandStrong ?? this.brandStrong,
    interactive: interactive ?? this.interactive,
    controlPrimary: controlPrimary ?? this.controlPrimary,
    interactiveStrong: interactiveStrong ?? this.interactiveStrong,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    info: info ?? this.info,
    selection: selection ?? this.selection,
    review: review ?? this.review,
  );

  @override
  ButlerlySemanticColors lerp(
    covariant ThemeExtension<ButlerlySemanticColors>? other,
    double t,
  ) {
    if (other is! ButlerlySemanticColors) return this;
    return ButlerlySemanticColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      elevatedSurface: Color.lerp(elevatedSurface, other.elevatedSurface, t)!,
      subtleSurface: Color.lerp(subtleSurface, other.subtleSurface, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      tertiaryText: Color.lerp(tertiaryText, other.tertiaryText, t)!,
      cardDivider: Color.lerp(cardDivider, other.cardDivider, t)!,
      border: Color.lerp(border, other.border, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandStrong: Color.lerp(brandStrong, other.brandStrong, t)!,
      interactive: Color.lerp(interactive, other.interactive, t)!,
      controlPrimary: Color.lerp(controlPrimary, other.controlPrimary, t)!,
      interactiveStrong: Color.lerp(
        interactiveStrong,
        other.interactiveStrong,
        t,
      )!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      review: Color.lerp(review, other.review, t)!,
    );
  }
}

extension ButlerlyThemeContext on BuildContext {
  ButlerlySemanticColors get colors =>
      Theme.of(this).extension<ButlerlySemanticColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? ButlerlySemanticColors.dark
          : ButlerlySemanticColors.light);
}
