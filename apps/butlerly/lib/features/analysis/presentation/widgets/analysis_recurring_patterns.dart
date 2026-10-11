import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class AnalysisRecurringPatterns extends StatelessWidget {
  const AnalysisRecurringPatterns({
    super.key,
    required this.patterns,
    required this.masterData,
    this.onConfirm,
    this.onReject,
    this.onCorrect,
  });

  final Future<ApplicationResult<List<RecurringPattern>>> patterns;
  final TransactionMasterData? masterData;
  final Future<void> Function(RecurringPattern pattern)? onConfirm;
  final Future<void> Function(RecurringPattern pattern)? onReject;
  final Future<void> Function(RecurringPattern pattern, DecimalValue amount)?
  onCorrect;

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<ApplicationResult<List<RecurringPattern>>>(
    future: patterns,
    builder: (context, snapshot) {
      final result = snapshot.data;
      if (snapshot.connectionState != ConnectionState.done) {
        return ButlerlyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ButlerlyCardHeader(title: context.l10n.text('recurringPatterns')),
              Text(context.l10n.text('recurringPatternsLoading')),
            ],
          ),
        );
      }
      if (result is! ApplicationSuccess<List<RecurringPattern>>) {
        return ButlerlyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ButlerlyCardHeader(title: context.l10n.text('recurringPatterns')),
              Text(context.l10n.text('recurringPatternsUnavailable')),
            ],
          ),
        );
      }
      if (result.value.isEmpty) return const SizedBox.shrink();
      return ButlerlyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ButlerlyCardHeader(title: context.l10n.text('recurringPatterns')),
            Text(context.l10n.text('recurringPatternsBody')),
            const SizedBox(height: ButlerlySpacing.compact),
            for (final pattern in result.value) ...[
              if (pattern != result.value.first)
                const SizedBox(height: ButlerlySpacing.compact),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      masterData?.merchantName(pattern.merchantId?.value) ??
                          pattern.counterparty ??
                          context.l10n.text('unavailableMerchant'),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(width: ButlerlySpacing.compact),
                  Flexible(
                    child: Text(
                      '${_cadenceLabel(context, pattern.cadence)} · ${localizedDecimal(context, (pattern.confidence * 100).round().toString())}%',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              Text(
                _statusLabel(context, pattern.status),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: ButlerlySpacing.micro),
              Text(
                '${context.l10n.text('recurringExpectedAmount')}: '
                '${localizedCompactMoney(context, pattern.expectedAmount.toString(), pattern.currency.value)}',
              ),
              if (pattern.expectedNextDate != null)
                Text(
                  '${context.l10n.text('recurringNextOccurrence')}: '
                  '${_localizedDate(context, pattern.expectedNextDate!)}',
                ),
              if (pattern.qualityIssues.isNotEmpty)
                Text(
                  context.l10n.text('dataQualityNeedsAttention', {
                    'count': localizedDecimal(
                      context,
                      pattern.qualityIssues.length.toString(),
                    ),
                  }),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Wrap(
                spacing: ButlerlySpacing.compact,
                children: [
                  if (pattern.status != RecurringPatternStatus.confirmed)
                    TextButton(
                      onPressed: onConfirm == null
                          ? null
                          : () => onConfirm!(pattern),
                      child: Text(context.l10n.text('recurringPatternConfirm')),
                    ),
                  if (pattern.status != RecurringPatternStatus.rejected)
                    TextButton(
                      onPressed: onReject == null
                          ? null
                          : () => onReject!(pattern),
                      child: Text(context.l10n.text('recurringPatternReject')),
                    ),
                  TextButton(
                    onPressed: onCorrect == null
                        ? null
                        : () => _correct(context, pattern),
                    child: Text(context.l10n.text('recurringPatternCorrect')),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );

  Future<void> _correct(BuildContext context, RecurringPattern pattern) async {
    final controller = TextEditingController(
      text: pattern.expectedAmount.toString(),
    );
    var invalid = false;
    final value = await showButlerlyBottomSheet<DecimalValue>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => ButlerlySheet(
          title: Text(sheetContext.l10n.text('recurringPatternCorrect')),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: sheetContext.l10n.text('recurringExpectedAmount'),
                ),
                onChanged: (_) {
                  if (invalid) setSheetState(() => invalid = false);
                },
              ),
              if (invalid) ...[
                const SizedBox(height: ButlerlySpacing.xs),
                Text(
                  sheetContext.l10n.text('invalidAmount'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            ButlerlyCancelButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(sheetContext.l10n.text('cancel')),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.pop(
                    sheetContext,
                    DecimalValue.parse(controller.text.trim()),
                  );
                } on Exception {
                  setSheetState(() => invalid = true);
                }
              },
              child: Text(sheetContext.l10n.text('save')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value != null) await onCorrect!(pattern, value);
  }
}

String _localizedDate(BuildContext context, String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  return MaterialLocalizations.of(
    context,
  ).formatMediumDate(DateTime.utc(date.year, date.month, date.day));
}

String _statusLabel(BuildContext context, RecurringPatternStatus status) =>
    switch (status) {
      RecurringPatternStatus.detected => context.l10n.text(
        'recurringPatternDetected',
      ),
      RecurringPatternStatus.confirmed => context.l10n.text(
        'recurringPatternConfirmed',
      ),
      RecurringPatternStatus.rejected => context.l10n.text(
        'recurringPatternRejected',
      ),
      RecurringPatternStatus.corrected => context.l10n.text(
        'recurringPatternCorrected',
      ),
    };

String _cadenceLabel(
  BuildContext context,
  RecurringCadence cadence,
) => switch (cadence) {
  RecurringCadence.weekly => context.l10n.text('recurringCadenceWeekly'),
  RecurringCadence.biweekly => context.l10n.text('recurringCadenceBiweekly'),
  RecurringCadence.monthly => context.l10n.text('recurringCadenceMonthly'),
  RecurringCadence.quarterly => context.l10n.text('recurringCadenceQuarterly'),
  RecurringCadence.irregular => context.l10n.text('recurringCadenceIrregular'),
};
