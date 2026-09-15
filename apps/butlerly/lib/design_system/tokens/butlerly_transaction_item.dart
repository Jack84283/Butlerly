import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:flutter/material.dart';

/// Layout values shared by every transaction-record list presentation.
abstract final class ButlerlyTransactionItemTokens {
  /// Reference-inspired row geometry. Components consume these semantic values
  /// instead of embedding presentation numbers in individual transaction rows.
  static const horizontalInset = ButlerlySpacing.small;
  static const topPadding = ButlerlySpacing.small;
  static const bottomPadding = ButlerlySpacing.small;
  static const categoryIconLeadingInset = ButlerlySpacing.none;
  static const leadingIconSize = ButlerlySize.preferredTarget;
  static const leadingIconGlyphSize = ButlerlySize.categoryIconGlyph;
  static const leadingIconTopInset = ButlerlySpacing.xxs;
  static const leadingToContentSpacing = ButlerlySpacing.compact;
  static const titleAmountSpacing = ButlerlySpacing.compact;
  static const headerSpacing = ButlerlySpacing.xxs;
  static const metadataSpacing = ButlerlySpacing.xxs;
  static const metadataTrailingInset = ButlerlySpacing.none;

  /// Typography roles measured from the transaction-list reference.
  static const titleFontSize = 15.0;
  static const titleLineHeight = 20 / 15;
  static const metadataFontSize = 14.0;
  static const metadataLineHeight = 18 / 14;
  static const amountFontSize = 17.0;
  static const amountLineHeight = 20 / 17;

  static const directionIconSize = 18.0;
  static const warningIconSize = 18.0;
  static const navigationIconSize = 18.0;
  static const dividerThickness = 1.0;
  static const dividerInset = horizontalInset;
  static const minTouchHeight =
      leadingIconSize + topPadding + bottomPadding;
  static const selectionControlTapTargetSize = MaterialTapTargetSize.shrinkWrap;
  static const selectionControlDensity = VisualDensity.compact;
  static const textHeightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );
}

/// Semantic styles for the transaction title, amount, and supporting metadata.
extension ButlerlyTransactionItemStyles on BuildContext {
  TextStyle get transactionItemAmount => Theme.of(this).textTheme.titleMedium!
      .copyWith(
        fontSize: ButlerlyTransactionItemTokens.amountFontSize,
        height: ButlerlyTransactionItemTokens.amountLineHeight,
        fontWeight: FontWeight.w600,
        color: colors.primaryText,
        fontFeatures: ButlerlyTypography.financialAmountFeatures,
      );

  TextStyle get transactionItemDate => Theme.of(this).textTheme.bodyMedium!
      .copyWith(
        fontSize: ButlerlyTransactionItemTokens.metadataFontSize,
        height: ButlerlyTransactionItemTokens.metadataLineHeight,
        fontWeight: FontWeight.w400,
        color: colors.secondaryText,
      );

  TextStyle get transactionItemDescription => Theme.of(this)
      .textTheme
      .bodyMedium!
      .copyWith(
        fontSize: ButlerlyTransactionItemTokens.titleFontSize,
        height: ButlerlyTransactionItemTokens.titleLineHeight,
        fontWeight: FontWeight.w600,
        color: colors.primaryText,
      );

  TextStyle get transactionItemMetadata => Theme.of(this).textTheme.bodyMedium!
      .copyWith(
        fontSize: ButlerlyTransactionItemTokens.metadataFontSize,
        height: ButlerlyTransactionItemTokens.metadataLineHeight,
        fontWeight: FontWeight.w400,
        color: colors.secondaryText,
      );

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
