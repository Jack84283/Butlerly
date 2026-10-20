import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';

/// Shared geometry for all Butlerly button roles.
abstract final class ButlerlyButtonTokens {
  static const height = 32.0;
  static const compactHeight = height;
  static const iconSize = 18.0;

  /// Minimum visual width for text actions (icon-only controls are exempt).
  static const minimumWidth = 120.0;

  /// Canonical width for normal text actions.
  static const standardWidth = 120.0;
  static const horizontalPadding = ButlerlySpacing.small;
  static const verticalPadding = ButlerlySpacing.micro;
  static const compactVisualHeight = height;
  static const compactMinimumHeight = minimumWidth;
  static const compactHorizontalPadding = ButlerlySpacing.small;
  static const compactVerticalPadding = ButlerlySpacing.micro;
  static const iconTouchTarget = ButlerlySize.minimumTarget;
  static const iconVisualSize = 32.0;
  static const radius = ButlerlyRadius.full;
}
