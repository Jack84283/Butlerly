import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';

/// Identical spending-trend bar and month-label colors for device and desktop.
///
/// The active month uses the chosen appearance/color theme's interactive
/// accent. All other valid months use a neutral, muted gray independent of
/// the accent hue. Missing/unavailable months keep their separate icon.
abstract final class ButlerlySpendingTrendColors {
  static Color bar(BuildContext context, {required bool selected}) => selected
      ? context.colors.interactive
      : context.colors.tertiaryText.withValues(alpha: 0.55);

  static Color label(BuildContext context, {required bool selected}) =>
      selected ? context.colors.interactive : context.colors.tertiaryText;
}
