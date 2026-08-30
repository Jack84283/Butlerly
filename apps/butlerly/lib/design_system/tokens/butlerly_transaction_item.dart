import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';

/// Layout values shared by every transaction-record list presentation.
abstract final class ButlerlyTransactionItemTokens {
  static const horizontalInset = 12.0;
  static const verticalPadding = 8.0;
  static const directionIconSize = 18.0;
  static const warningIconSize = 18.0;
  static const headerSpacing = 4.0;
  static const dividerThickness = 1.0;
  static const dividerInset = 12.0;
  static const minTouchHeight = 72.0;
}

/// Semantic styles for the three lines and indicators in a transaction row.
extension ButlerlyTransactionItemStyles on BuildContext {
  TextStyle get transactionItemAmount =>
      Theme.of(this).textTheme.titleMedium!.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: FontWeight.w700,
      );

  TextStyle get transactionItemDate => Theme.of(this).textTheme.bodySmall!;

  TextStyle get transactionItemDescription =>
      Theme.of(this).textTheme.bodyMedium!;

  TextStyle get transactionItemMetadata => Theme.of(this).textTheme.bodySmall!;

  Color transactionItemDirectionIcon(bool isIncome) =>
      isIncome ? colors.success : colors.primaryText;

  Color get transactionItemWarningIcon => colors.warning;

  Color get transactionItemDivider => colors.cardDivider;
}
