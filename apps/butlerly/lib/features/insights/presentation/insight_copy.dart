import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';

enum InsightCopyKey {
  categoryMovementSubtitle,
  subcategoryMovementSubtitle,
  merchantMovementSubtitle,
  viewSupportingTransaction,
  viewSupportingTransactions,
}

String insightCopy(
  BuildContext context,
  InsightCopyKey key, {
  int? count,
}) {
  final locale = AppLocalizations.of(context).locale.languageCode;
  final language = _copy.containsKey(locale) ? locale : 'en';
  var value = _copy[language]![key]!;
  if (count != null) {
    value = value.replaceAll('{count}', '$count');
  }
  return value;
}

const _copy = <String, Map<InsightCopyKey, String>>{
  'en': {
    InsightCopyKey.categoryMovementSubtitle:
        'Categories changed materially compared with the previous equivalent period.',
    InsightCopyKey.subcategoryMovementSubtitle:
        'Subcategories changed materially compared with the previous equivalent period.',
    InsightCopyKey.merchantMovementSubtitle:
        'Merchant spending changed materially compared with the previous equivalent period.',
    InsightCopyKey.viewSupportingTransaction:
        'View {count} supporting transaction',
    InsightCopyKey.viewSupportingTransactions:
        'View {count} supporting transactions',
  },
  'es': {
    InsightCopyKey.categoryMovementSubtitle:
        'Las categorías cambiaron de forma significativa respecto al período equivalente anterior.',
    InsightCopyKey.subcategoryMovementSubtitle:
        'Las subcategorías cambiaron de forma significativa respecto al período equivalente anterior.',
    InsightCopyKey.merchantMovementSubtitle:
        'El gasto por comercio cambió de forma significativa respecto al período equivalente anterior.',
    InsightCopyKey.viewSupportingTransaction:
        'Ver {count} transacción de respaldo',
    InsightCopyKey.viewSupportingTransactions:
        'Ver {count} transacciones de respaldo',
  },
  'zh': {
    InsightCopyKey.categoryMovementSubtitle: '类别与上一等效期间相比发生了显著变化。',
    InsightCopyKey.subcategoryMovementSubtitle: '子类别与上一等效期间相比发生了显著变化。',
    InsightCopyKey.merchantMovementSubtitle: '商户支出与上一等效期间相比发生了显著变化。',
    InsightCopyKey.viewSupportingTransaction: '查看 {count} 笔支持交易',
    InsightCopyKey.viewSupportingTransactions: '查看 {count} 笔支持交易',
  },
};
