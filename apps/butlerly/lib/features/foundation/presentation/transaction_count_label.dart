import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

String transactionCountLabel(BuildContext context, int count) {
  final l10n = AppLocalizations.of(context);
  return count == 1
      ? l10n.text('oneTransaction')
      : l10n.text('manyTransactions', {'count': '$count'});
}

class TransactionCountText extends StatelessWidget {
  const TransactionCountText({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: transactionCountLabel(context, count),
    child: Text(
      transactionCountLabel(context, count),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
