import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A staged custom-period editor. The committed range is only returned after
/// the user presses Save; dismissing the sheet leaves it unchanged.
class AnalysisCustomPeriodSheet extends StatefulWidget {
  const AnalysisCustomPeriodSheet({required this.initialRange, super.key});

  final DateTimeRange initialRange;

  @override
  State<AnalysisCustomPeriodSheet> createState() =>
      _AnalysisCustomPeriodSheetState();
}

class _AnalysisCustomPeriodSheetState extends State<AnalysisCustomPeriodSheet> {
  late DateTime _start;
  late DateTime _end;
  bool _editingEnd = false;

  @override
  void initState() {
    super.initState();
    _start = _dateOnly(widget.initialRange.start);
    _end = _dateOnly(widget.initialRange.end);
    if (_end.isBefore(_start)) _end = _start;
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  void _select(DateTime value) {
    final date = _dateOnly(value);
    setState(() {
      if (_editingEnd) {
        _end = date.isBefore(_start) ? _start : date;
      } else {
        _start = date;
        if (_end.isBefore(_start)) _end = _start;
      }
    });
  }

  String _format(BuildContext context, DateTime value) =>
      MaterialLocalizations.of(context).formatMediumDate(value);

  @override
  Widget build(BuildContext context) => ButlerlySheet(
    title: Text(context.l10n.text('selectRange')),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _DateChoice(
                key: const ValueKey('analysis-custom-period-from'),
                label: context.l10n.text('from'),
                value: _format(context, _start),
                selected: !_editingEnd,
                onTap: () => setState(() => _editingEnd = false),
              ),
            ),
            const SizedBox(width: ButlerlySpacing.compact),
            Expanded(
              child: _DateChoice(
                key: const ValueKey('analysis-custom-period-to'),
                label: context.l10n.text('to'),
                value: _format(context, _end),
                selected: _editingEnd,
                onTap: () => setState(() => _editingEnd = true),
              ),
            ),
          ],
        ),
        const SizedBox(height: ButlerlySpacing.standard),
        CalendarDatePicker(
          initialDate: _editingEnd ? _end : _start,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          currentDate: DateTime.now(),
          onDateChanged: _select,
        ),
      ],
    ),
    actions: [
      TextButton(
        key: const ValueKey('analysis-custom-period-cancel'),
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.text('cancel')),
      ),
      FilledButton(
        key: const ValueKey('analysis-custom-period-save'),
        onPressed: () =>
            Navigator.pop(context, DateTimeRange(start: _start, end: _end)),
        child: Text(context.l10n.text('save')),
      ),
    ],
  );
}

class _DateChoice extends StatelessWidget {
  const _DateChoice({
    super.key,
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$label, $value',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ButlerlySpacing.compact),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: selected ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
