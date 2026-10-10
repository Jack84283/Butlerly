import 'package:butlerly/design_system/components/butlerly_transaction_inner_card.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transaction_record_list.dart';
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
    required this.onTransactionTap,
    this.masterData,
  });
  final String date;
  final Future<ApplicationResult<List<TransactionDto>>>? result;
  final Money? expense;
  final ValueChanged<TransactionDto> onTransactionTap;
  final TransactionMasterData? masterData;

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
        padding: const EdgeInsets.only(top: ButlerlySpacing.micro),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ButlerlySpacing.standard,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    MaterialLocalizations.of(
                      context,
                    ).formatFullDate(DateTime.parse(date)),
                    key: const ValueKey('analysis-selected-day-date'),
                  ),
                  Text(
                    '${localizedCount(context, value.value.length.toString())} ${context.l10n.text('transactions')}${expense == null ? '' : ' · ${analysisMoneyValue(context, expense!)} ${context.l10n.text('spent')}'}',
                    key: const ValueKey('analysis-selected-day-summary'),
                  ),
                ],
              ),
            ),
            if (value.value.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ButlerlySpacing.standard,
                ),
                child: Text(context.l10n.text('noTransactions')),
              ),
            if (value.value.isNotEmpty) ...[
              const SizedBox(height: ButlerlySpacing.micro),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ButlerlySpacing.small,
                ),
                child: ButlerlyTransactionInnerCard(
                  child: TransactionRecordList(
                    transactions: value.value,
                    masterData: masterData ?? const TransactionMasterData(),
                    onTap: onTransactionTap,
                    dashboardRowStyle: true,
                    showDateInRows: true,
                    missingCategoryLabel: context.l10n.text('uncategorized'),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}
