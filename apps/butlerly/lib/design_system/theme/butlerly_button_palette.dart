import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';

/// Contrast-forward button roles shared by both Butlerly brightness modes.
///
/// Accent roles come from the active color theme; neutral control surfaces
/// are deliberately distinct from dashboard cards and bottom sheets.
@immutable
final class ButlerlyButtonPalette {
  const ButlerlyButtonPalette({
    required this.primaryFill,
    required this.secondaryFill,
    required this.secondaryBorder,
    required this.secondaryText,
    required this.tertiaryFill,
    required this.tertiaryBorder,
    required this.tertiaryText,
    required this.destructiveFill,
    required this.destructiveBorder,
    required this.destructiveText,
    required this.compactFill,
    required this.compactBorder,
    required this.compactText,
    required this.chipFill,
    required this.chipBorder,
    required this.segmentFill,
    required this.segmentBorder,
    required this.iconBorder,
  });

  final Color primaryFill;
  final Color secondaryFill;
  final Color secondaryBorder;
  final Color secondaryText;
  final Color tertiaryFill;
  final Color tertiaryBorder;
  final Color tertiaryText;
  final Color destructiveFill;
  final Color destructiveBorder;
  final Color destructiveText;
  final Color compactFill;
  final Color compactBorder;
  final Color compactText;
  final Color chipFill;
  final Color chipBorder;
  final Color segmentFill;
  final Color segmentBorder;
  final Color iconBorder;

  static ButlerlyButtonPalette resolve({
    required ButlerlySemanticColors colors,
    required Brightness brightness,
  }) {
    final dark = brightness == Brightness.dark;
    final primaryFill = dark
        ? Color.lerp(colors.controlPrimary, colors.interactiveStrong, 0.35)!
        : colors.controlPrimary;
    final secondaryFill = dark
        ? const Color(0xFF353D52)
        : Color.alphaBlend(
            colors.brand.withValues(alpha: 0.09),
            colors.cardSurface,
          );
    final secondaryBorder = dark ? const Color(0xFF8993A8) : colors.brand;
    final tertiaryFill = dark ? Colors.transparent : const Color(0xFFE9EDF3);
    final tertiaryBorder = dark
        ? const Color(0xFF8993A8)
        : const Color(0xFFAAB6C8);
    final destructiveFill = Color.alphaBlend(
      colors.error.withValues(alpha: dark ? 0.2 : 0.09),
      dark ? colors.elevatedSurface : colors.cardSurface,
    );

    return ButlerlyButtonPalette(
      primaryFill: primaryFill,
      secondaryFill: secondaryFill,
      secondaryBorder: secondaryBorder,
      secondaryText: dark ? colors.primaryText : colors.brand,
      tertiaryFill: tertiaryFill,
      tertiaryBorder: tertiaryBorder,
      tertiaryText: dark ? colors.primaryText : colors.secondaryText,
      destructiveFill: destructiveFill,
      destructiveBorder: colors.error,
      destructiveText: colors.error,
      compactFill: dark
          ? primaryFill
          : Color.alphaBlend(
              colors.brand.withValues(alpha: 0.07),
              colors.cardSurface,
            ),
      compactBorder: dark ? primaryFill : colors.brand,
      compactText: dark ? Colors.white : colors.brand,
      chipFill: dark ? secondaryFill : const Color(0xFFE9EDF3),
      chipBorder: dark ? const Color(0xFF8993A8) : const Color(0xFFBAC4D2),
      segmentFill: dark ? secondaryFill : colors.subtleSurface,
      segmentBorder: dark ? const Color(0xFF8993A8) : colors.border,
      iconBorder: tertiaryBorder,
    );
  }
}
