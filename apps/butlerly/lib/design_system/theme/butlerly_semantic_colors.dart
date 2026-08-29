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
    required this.interactiveStrong,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.selection,
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
  final Color interactiveStrong;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color selection;

  static const dark = ButlerlySemanticColors(
    background: Color(0xFF0B0B0D),
    surface: Color(0xFF141418),
    elevatedSurface: Color.fromRGBO(58, 58, 58, 1),
    subtleSurface: Color(0xFF111114),
    primaryText: Color(0xFFFFFFFF),
    secondaryText: Color.fromRGBO(228, 228, 228, 1),
    tertiaryText: Color.fromRGBO(228, 228, 228, 1),
    cardDivider: Color.fromRGBO(78, 78, 78, 1),
    border: Color(0xFF2A2A31),
    brand: Color(0xFFB42333),
    brandStrong: Color(0xFF7A1825),
    interactive: Color(0xFFE03A3E),
    interactiveStrong: Color(0xFFB42333),
    success: Color(0xFF2E9D64),
    warning: Color(0xFFD6A84B),
    error: Color(0xFFE06464),
    info: Color(0xFF5A9BD5),
    selection: Color(0xFF3A151B),
  );

  static const light = ButlerlySemanticColors(
    background: Color(0xFFF7F7F8),
    surface: Color(0xFFFFFFFF),
    elevatedSurface: Color.fromRGBO(218, 218, 218, 1),
    subtleSurface: Color(0xFFF2F2F4),
    primaryText: Color(0xFF171719),
    secondaryText: Color.fromRGBO(96, 96, 96, 1),
    tertiaryText: Color.fromRGBO(96, 96, 96, 1),
    cardDivider: Color.fromRGBO(198, 198, 198, 1),
    border: Color(0xFFDDDDE2),
    brand: Color(0xFFA51F2E),
    brandStrong: Color(0xFF741722),
    interactive: Color(0xFFB42333),
    interactiveStrong: Color(0xFFA51F2E),
    success: Color(0xFF2F855A),
    warning: Color(0xFF9A6A16),
    error: Color(0xFFB83A3A),
    info: Color(0xFF3278A8),
    selection: Color(0xFFF5E1E4),
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
            ? const Color(0xFF4D9DE0)
            : const Color(0xFF2878B5),
        brandStrong: brightness == Brightness.dark
            ? const Color(0xFF2D6FA3)
            : const Color(0xFF1D5C8C),
        interactive: brightness == Brightness.dark
            ? const Color(0xFF69B4F0)
            : const Color(0xFF2878B5),
        interactiveStrong: brightness == Brightness.dark
            ? const Color(0xFF4D9DE0)
            : const Color(0xFF1D5C8C),
        selection: brightness == Brightness.dark
            ? const Color(0xFF142B3D)
            : const Color(0xFFE0F0FA),
      ),
      ButlerlyColorTheme.green => base.copyWith(
        brand: brightness == Brightness.dark
            ? const Color(0xFF4CAF7A)
            : const Color(0xFF287A52),
        brandStrong: brightness == Brightness.dark
            ? const Color(0xFF2F815A)
            : const Color(0xFF1D5F3E),
        interactive: brightness == Brightness.dark
            ? const Color(0xFF65C58D)
            : const Color(0xFF287A52),
        interactiveStrong: brightness == Brightness.dark
            ? const Color(0xFF4CAF7A)
            : const Color(0xFF1D5F3E),
        selection: brightness == Brightness.dark
            ? const Color(0xFF153326)
            : const Color(0xFFE1F2E8),
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
    Color? interactiveStrong,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? selection,
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
    interactiveStrong: interactiveStrong ?? this.interactiveStrong,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    info: info ?? this.info,
    selection: selection ?? this.selection,
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
