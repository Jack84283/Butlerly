import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class AnalysisPeriodSelector extends StatelessWidget {
  const AnalysisPeriodSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: const ValueKey('analysis-period-selector'),
    initialValue: value,
    decoration: InputDecoration(labelText: context.l10n.text('analysisPeriod')),
    items: [
      for (final item in const [
        ('current_month', 'thisMonth'),
        ('previous_month', 'lastMonth'),
        ('year_to_date', 'yearToDate'),
        ('rolling_30_days', 'last30Days'),
        ('rolling_90_days', 'last90Days'),
        ('selected_period', 'custom'),
      ])
        DropdownMenuItem(
          value: item.$1,
          child: Text(context.l10n.text(item.$2)),
        ),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}
