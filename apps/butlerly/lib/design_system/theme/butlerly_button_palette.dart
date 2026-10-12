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
  });

  final Color primaryFill;
  final Color secondaryFill;
  final Color secondaryBorder;
  final Color secondaryText;
  final Color tertiaryFill;
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

  static ButlerlyButtonPalette resolve({
    required ButlerlySemanticColors colors,
    required Brightness brightness,
  }) {
    final dark = brightness == Brightness.dark;
    // Keep existing component treatments; only their colors come from the
    // shared light/dark semantic palette.
    final primaryFill = colors.controlPrimary;
    final secondaryFill = colors.cardSurface;
    final tertiaryFill = dark ? colors.elevatedSurface : colors.subtleSurface;
    final destructiveFill = Color.alphaBlend(
      colors.error.withValues(alpha: dark ? 0.2 : 0.09),
      dark ? colors.elevatedSurface : colors.cardSurface,
    );

    return ButlerlyButtonPalette(
      primaryFill: primaryFill,
      secondaryFill: secondaryFill,
      secondaryBorder: colors.border,
      secondaryText: colors.primaryText,
      tertiaryFill: tertiaryFill,
      tertiaryText: colors.primaryText,
      destructiveFill: destructiveFill,
      destructiveBorder: colors.error,
      destructiveText: colors.error,
      compactFill: colors.cardSurface,
      compactBorder: colors.border,
      compactText: colors.primaryText,
      chipFill: tertiaryFill,
      chipBorder: colors.border,
      segmentFill: dark ? colors.surface : colors.subtleSurface,
      segmentBorder: colors.border,
    );
  }
}
