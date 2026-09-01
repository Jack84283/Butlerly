import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class AnalysisDaySummary extends StatelessWidget {
  const AnalysisDaySummary({
    super.key,
    required this.date,
    required this.result,
    required this.expense,
    required this.onViewTransactions,
  });
  final String date;
  final Future<ApplicationResult<List<TransactionDto>>>? result;
  final Money? expense;
  final VoidCallback onViewTransactions;

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<ApplicationResult<List<TransactionDto>>>(
    future: result,
    builder: (context, snapshot) {
      final value = snapshot.data;
      if (value is! ApplicationSuccess<List<TransactionDto>>) {
        return const Padding(
          padding: EdgeInsets.only(top: ButlerlySpacing.small),
          child: LinearProgressIndicator(),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(top: ButlerlySpacing.small),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$date · ${localizedCount(context, value.value.length.toString())} ${context.l10n.text('transactions')}${expense == null ? '' : ' · ${analysisMoneyValue(context, expense!)} ${context.l10n.text('spent')}'}',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onViewTransactions,
                child: Text(context.l10n.text('viewTransactions')),
              ),
            ),
            if (value.value.isEmpty) Text(context.l10n.text('noTransactions')),
            for (final transaction in value.value.take(3))
              ListTile(
                key: ValueKey(
                  'analysis-calendar-transaction-${transaction.id}',
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  transaction.description?.trim().isNotEmpty == true
                      ? transaction.description!
                      : context.l10n.text('untitledTransaction'),
                ),
                subtitle: Text(
                  transactionDateLabel(
                    transaction,
                    pendingLabel: context.l10n.text('pending'),
                    locale: Localizations.localeOf(context).toLanguageTag(),
                  ),
                ),
                trailing: Text(
                  '${localizedTransactionAmount(context, transaction.amount)} ${transaction.currency}',
                ),
              ),
          ],
        ),
      );
    },
  );
}
