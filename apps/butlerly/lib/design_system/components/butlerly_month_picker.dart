import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Shared month picker for device and desktop Home.
class ButlerlyMonthPicker extends StatefulWidget {
  const ButlerlyMonthPicker({
    required this.selectedMonth,
    required this.currentMonth,
    super.key,
  });

  final DateTime selectedMonth;
  final DateTime currentMonth;

  @override
  State<ButlerlyMonthPicker> createState() => _ButlerlyMonthPickerState();
}

class _ButlerlyMonthPickerState extends State<ButlerlyMonthPicker> {
  late int _year = widget.selectedMonth.year;

  bool _isFuture(DateTime month) =>
      month.year > widget.currentMonth.year ||
      (month.year == widget.currentMonth.year &&
          month.month > widget.currentMonth.month);

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final colors = context.colors;
    return ButlerlySheet(
      title: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).previousMonthTooltip,
            onPressed: () => setState(() => _year--),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(child: Text('$_year', textAlign: TextAlign.center)),
          IconButton(
            tooltip: MaterialLocalizations.of(context).nextMonthTooltip,
            onPressed: _year < widget.currentMonth.year
                ? () => setState(() => _year++)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 12,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisExtent: 44,
            crossAxisSpacing: ButlerlySpacing.compact,
            mainAxisSpacing: ButlerlySpacing.compact,
          ),
          itemBuilder: (context, index) {
            final candidate = DateTime(_year, index + 1);
            final selected = candidate.year == widget.selectedMonth.year &&
                candidate.month == widget.selectedMonth.month;
            final disabled = _isFuture(candidate);
            final label = DateFormat.MMM(locale).format(candidate);
            return TextButton(
              key: Key('home-month-${candidate.year}-${candidate.month}'),
              onPressed: disabled ? null : () => Navigator.of(context).pop(candidate),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, ButlerlySize.minimumTarget),
                padding: EdgeInsets.zero,
                backgroundColor: Colors.transparent,
                side: BorderSide.none,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Center(
                child: SizedBox(
                  height: 32,
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected ? colors.controlPrimary : colors.cardSurface,
                      border: selected ? null : Border.all(color: colors.border),
                      borderRadius: BorderRadius.circular(ButlerlyRadius.full),
                    ),
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: disabled
                              ? colors.tertiaryText
                              : selected
                                  ? colors.onControlPrimary
                                  : colors.primaryText,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Displays the common month selection bottom sheet and returns the selected month.
Future<DateTime?> showButlerlyMonthPicker(
  BuildContext context, {
  required DateTime selectedMonth,
  required DateTime currentMonth,
}) => showButlerlyBottomSheet<DateTime>(
  context: context,
  builder: (_) => ButlerlyMonthPicker(
    selectedMonth: selectedMonth,
    currentMonth: currentMonth,
  ),
);
