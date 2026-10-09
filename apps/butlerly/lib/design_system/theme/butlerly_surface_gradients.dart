import 'package:flutter/material.dart';

/// Light-mode gradients supplement the solid semantic fallbacks.
/// Dark mode deliberately stays flat to preserve its near-black foundation.
abstract final class ButlerlySurfaceGradients {
  static const lightPage = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFEEF0F6),
      Color(0xFFE6E9EF),
      Color(0xFFDCE1E9),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const lightCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE1E5ED),
      Color(0xFFD6DBE3),
      Color(0xFFCDD4DF),
    ],
  );

  static const lightSurface = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFD3D9E3), Color(0xFFC8CED8)],
  );

  static const lightElevated = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC7CED9), Color(0xFFBCC4CF)],
  );

  static Gradient? page(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightPage : null;

  static Gradient? card(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightCard : null;

  static Gradient? surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightSurface : null;

  static Gradient? elevated(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightElevated : null;
}
