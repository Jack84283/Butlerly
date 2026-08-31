import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

String localizedReconciliationReason(BuildContext context, String value) =>
    switch (value) {
      'amount and currency match' => context.l10n.text(
        'reconciliationReasonAmountCurrencyMatch',
      ),
      'amount is within 10% (possible tip or adjustment)' => context.l10n.text(
        'reconciliationReasonAmountWithinTenPercent',
      ),
      'transaction date matches' => context.l10n.text(
        'reconciliationReasonDateMatches',
      ),
      'transaction date is within one day' => context.l10n.text(
        'reconciliationReasonDateWithinOneDay',
      ),
      'merchant text matches' => context.l10n.text(
        'reconciliationReasonMerchantMatches',
      ),
      'merchant text is similar' => context.l10n.text(
        'reconciliationReasonMerchantSimilar',
      ),
      'payment source matches' => context.l10n.text(
        'reconciliationReasonPaymentSourceMatches',
      ),
      _ => context.l10n.text('reconciliationReasonOther'),
    };

String localizedReconciliationConflict(
  BuildContext context,
  String value,
) => switch (value) {
  'transaction direction conflicts' => context.l10n.text(
    'reconciliationConflictDirection',
  ),
  'currency conflicts' => context.l10n.text('reconciliationConflictCurrency'),
  'amount differs' => context.l10n.text('reconciliationConflictAmount'),
  'transaction date differs' => context.l10n.text('reconciliationConflictDate'),
  'merchant text differs' => context.l10n.text(
    'reconciliationConflictMerchant',
  ),
  'payment source differs' => context.l10n.text(
    'reconciliationConflictPaymentSource',
  ),
  _ => context.l10n.text('reconciliationConflictOther'),
};

String localizedReconciliationReasons(
  BuildContext context,
  Iterable<String> values,
) => values
    .map((value) => localizedReconciliationReason(context, value))
    .join('; ');

String localizedReconciliationConflicts(
  BuildContext context,
  Iterable<String> values,
) => values
    .map((value) => localizedReconciliationConflict(context, value))
    .join('; ');
