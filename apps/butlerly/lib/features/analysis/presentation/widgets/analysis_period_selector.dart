import 'dart:math' as math;

import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
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
  Widget build(BuildContext context) => ButlerlySelectField<String>(
    key: const ValueKey('analysis-period-selector'),
    label: context.l10n.text('analysisPeriod'),
    // A month handed off from Home retains selected_month semantics in the
    // application layer. The selector represents it through the existing
    // custom control rather than exposing an incomplete standalone option.
    value: value == 'selected_month' ? 'selected_period' : value,
    entries: [
      for (final item in const [
        ('current_month', 'thisMonth'),
        ('previous_month', 'lastMonth'),
        ('year_to_date', 'yearToDate'),
        ('rolling_30_days', 'last30Days'),
        ('rolling_90_days', 'last90Days'),
        ('selected_period', 'custom'),
      ])
        DropdownMenuEntry(value: item.$1, label: context.l10n.text(item.$2)),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}

class AnalysisPeriodPinnedHeader extends StatelessWidget {
  const AnalysisPeriodPinnedHeader({
    super.key,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  static double extent(BuildContext context, String subtitle) {
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final maxWidth =
        MediaQuery.sizeOf(context).width - ButlerlySize.phoneGutter * 2;
    final subtitleHeight = _textHeight(
      subtitle,
      style: theme.textTheme.bodyMedium!,
      textScaler: textScaler,
      textDirection: textDirection,
      maxWidth: maxWidth,
    );
    final selectorTextStyle = theme.textTheme.bodyLarge!;
    final selectorLabel = context.l10n.text('analysisPeriod');
    final baseSelectorTextHeight = _textHeight(
      selectorLabel,
      style: selectorTextStyle,
      textScaler: TextScaler.noScaling,
      textDirection: textDirection,
      maxWidth: maxWidth,
    );
    final scaledSelectorTextHeight = _textHeight(
      selectorLabel,
      style: selectorTextStyle,
      textScaler: textScaler,
      textDirection: textDirection,
      maxWidth: maxWidth,
    );
    final selectorHeight =
        ButlerlySize.analysisPeriodSelectorHeight +
        math.max(0.0, scaledSelectorTextHeight - baseSelectorTextHeight);
    return ButlerlySpacing.pinnedHeaderVerticalPadding * 2 +
        subtitleHeight +
        ButlerlySpacing.periodSelectorGap +
        selectorHeight;
  }

  static double _textHeight(
    String text, {
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
    required double maxWidth,
  }) {
    final painter =
        TextPainter(
          text: TextSpan(text: text, style: style),
          textScaler: textScaler,
          textDirection: textDirection,
          maxLines: 1,
        )..layout(maxWidth: maxWidth);
    return painter.height;
  }

  final String subtitle;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      vertical: ButlerlySpacing.pinnedHeaderVerticalPadding,
    ),
    child: Column(
      key: const ValueKey('analysis-period-pinned-header'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: ButlerlySpacing.periodSelectorGap),
        AnalysisPeriodSelector(value: value, onChanged: onChanged),
      ],
    ),
  );
}
