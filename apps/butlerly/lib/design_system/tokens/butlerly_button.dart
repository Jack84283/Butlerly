import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';

/// Shared geometry for all Butlerly button roles.
abstract final class ButlerlyButtonTokens {
  static const height = ButlerlySize.preferredTarget;
  static const compactHeight = ButlerlySize.minimumTarget;
  static const iconSize = 24.0;
  /// Minimum accessible width for compact and icon controls.
  static const minimumWidth = ButlerlySize.minimumTarget;
  /// Consistent recommended width for normal text actions.
  static const standardWidth = 120.0;
  static const horizontalPadding = ButlerlySpacing.standard;
  static const verticalPadding = ButlerlySpacing.small;
  static const compactVisualHeight = 40.0;
  static const compactMinimumHeight = ButlerlySize.minimumTarget;
  static const compactHorizontalPadding = ButlerlySpacing.small;
  static const compactVerticalPadding = ButlerlySpacing.compact;
  static const radius = ButlerlyRadius.full;
}
