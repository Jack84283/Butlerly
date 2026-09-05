import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:flutter/material.dart';

/// Layout values shared by every transaction-record list presentation.
abstract final class ButlerlyTransactionItemTokens {
  static const horizontalInset = ButlerlySpacing.micro;
  static const topPadding = ButlerlySpacing.compact;
  static const bottomPadding = ButlerlySpacing.compact;

  /// Compensates for the row's horizontal inset so the icon's final left and
  /// top offsets from the item boundary are identical.
  static const categoryIconLeadingInset = topPadding - horizontalInset;
  static const directionIconSize = 18.0;
  static const warningIconSize = 18.0;
  static const navigationIconSize = 18.0;
  static const headerSpacing = ButlerlySpacing.micro;
  static const metadataTrailingInset = ButlerlySpacing.compact;
  static const dividerThickness = 1.0;
  static const dividerInset = ButlerlySpacing.micro;
  static const minTouchHeight = ButlerlySize.recordRowMinHeight;
  static const selectionControlTapTargetSize = MaterialTapTargetSize.shrinkWrap;
  static const selectionControlDensity = VisualDensity.compact;
  static const textHeightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );
}

/// Semantic styles for the three lines and indicators in a transaction row.
extension ButlerlyTransactionItemStyles on BuildContext {
  TextStyle get transactionItemAmount =>
      ButlerlyTypography.financialAmount(Theme.of(this).textTheme.titleMedium!);

  TextStyle get transactionItemDate => Theme.of(this).textTheme.bodySmall!;

  TextStyle get transactionItemDescription =>
      Theme.of(this).textTheme.bodyMedium!;

  TextStyle get transactionItemMetadata => Theme.of(this).textTheme.bodySmall!;

  Color transactionItemDirectionIcon(bool isIncome) =>
      isIncome ? colors.success : colors.primaryText;

  Color get transactionItemWarningIcon => colors.warning;

  Color get transactionItemNavigationIcon => colors.secondaryText;

  Color get transactionItemDivider => colors.cardDivider;
}

extension ButlerlyTransactionDetailStyles on BuildContext {
  TextStyle get transactionDetailAmount =>
      ButlerlyTypography.financialDetailAmount(
        Theme.of(this).textTheme.titleLarge!,
      );

  TextStyle get transactionDetailDescription =>
      Theme.of(this).textTheme.bodyMedium!;
}
