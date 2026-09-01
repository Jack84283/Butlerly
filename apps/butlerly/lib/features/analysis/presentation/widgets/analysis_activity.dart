import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_day_summary.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class AnalysisActivitySummary extends StatelessWidget {
  const AnalysisActivitySummary({super.key, required this.metric});
  final AnalysisMetric? metric;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    child: Text(
      metric == null
          ? context.l10n.text('noActivityInPeriod')
          : '${double.tryParse(metric!.value.toString())?.round() ?? 0} ${context.l10n.text('transactions')}',
    ),
  );
}

class AnalysisActivity extends StatelessWidget {
  const AnalysisActivity({
    super.key,
    required this.result,
    required this.selectedDate,
    required this.transactions,
    required this.onSelectDate,
    required this.onTransactionTap,
  });
  final Future<ApplicationResult<AnalysisCalendarResult>> result;
  final String? selectedDate;
  final Future<ApplicationResult<List<TransactionDto>>>? transactions;
  final ValueChanged<String> onSelectDate;
  final ValueChanged<TransactionDto> onTransactionTap;

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<ApplicationResult<AnalysisCalendarResult>>(
    future: result,
    builder: (context, snapshot) {
      final value = snapshot.data;
      if (snapshot.connectionState != ConnectionState.done) {
        return const ButlerlyCard(child: LinearProgressIndicator());
      }
      if (value is! ApplicationSuccess<AnalysisCalendarResult>) {
        return ButlerlyCard(
          child: Text(context.l10n.text('analysisUnavailable')),
        );
      }
      final calendar = value.value;
      final first = DateTime(calendar.year, calendar.month);
      final materialLocalizations = MaterialLocalizations.of(context);
      final firstDayOfWeek = materialLocalizations.firstDayOfWeekIndex;
      final leading = (first.weekday % 7 - firstDayOfWeek + 7) % 7;
      final todayDate = _financialDate(DateTime.now(), calendar.timeZoneId);
      return ButlerlyCard(
        child: Column(
          children: [
            Text(
              materialLocalizations.formatMonthYear(first),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: ButlerlySpacing.small),
            Row(
              children: [
                for (var weekday = 0; weekday < 7; weekday++)
                  Expanded(
                    child: Center(
                      child: Text(
                        materialLocalizations.narrowWeekdays[(firstDayOfWeek +
                                weekday) %
                            7],
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
              ],
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: leading + calendar.days.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemBuilder: (context, index) {
                if (index < leading) return const SizedBox.shrink();
                final day = calendar.days[index - leading];
                final selected = day.financialDate == selectedDate;
                final isToday = day.financialDate == todayDate;
                return Semantics(
                  label:
                      '${day.financialDate}, ${day.transactionCount} ${context.l10n.text('transactions')}${isToday ? ', ${context.l10n.text('today')}' : ''}',
                  selected: selected,
                  button: true,
                  child: InkWell(
                    key: ValueKey('analysis-calendar-${day.financialDate}'),
                    onTap: () => onSelectDate(day.financialDate),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: day.transactionCount == 0
                            ? null
                            : context.colors.selection,
                        border: selected
                            ? Border.all(
                                color: context.colors.interactive,
                                width: 2,
                              )
                            : null,
                        borderRadius: BorderRadius.circular(
                          ButlerlyRadius.small,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(day.financialDate.substring(8)),
                          if (day.transactionCount > 0)
                            Icon(
                              Icons.circle,
                              size: 5,
                              semanticLabel: context.l10n.text('activity'),
                              color: context.colors.interactive,
                            ),
                          if (isToday)
                            Text(
                              context.l10n.text('today'),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            if (selectedDate != null)
              AnalysisDaySummary(
                date: selectedDate!,
                result: transactions,
                expense: calendar.days
                    .where((day) => day.financialDate == selectedDate)
                    .firstOrNull
                    ?.expenseTotal,
                onTransactionTap: onTransactionTap,
              ),
          ],
        ),
      );
    },
  );
}

String _financialDate(DateTime value, String timeZoneId) =>
    financialDateAt(value, timeZoneId).toIso8601String().substring(0, 10);
