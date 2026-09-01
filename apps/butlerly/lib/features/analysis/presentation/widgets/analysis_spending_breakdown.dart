import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class AnalysisSpendingBreakdown extends StatelessWidget {
  const AnalysisSpendingBreakdown({
    super.key,
    required this.model,
    required this.masterData,
    this.onCategoryTap,
    this.onViewAll,
  });
  final AnalysisModel model;
  final TransactionMasterData? masterData;
  final ValueChanged<AnalysisMetric>? onCategoryTap;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    if (model.categories.isEmpty) {
      return ButlerlyCard(child: Text(context.l10n.text('noSpendingInPeriod')));
    }
    final max = model.categories
        .map(analysisNumber)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final chartValues = model.categories.take(5).toList(growable: false);
    final remainingValue = model.categories
        .skip(chartValues.length)
        .map(analysisNumber)
        .fold<double>(0, (sum, value) => sum + value);
    final chartSlices = [
      for (final metric in chartValues)
        _SpendingSlice(
          label: analysisDimension(context, metric, masterData),
          value: analysisNumber(metric),
          currency: metric.currency?.value,
        ),
      if (remainingValue > 0)
        _SpendingSlice(
          label: context.l10n.text('otherCategories'),
          value: remainingValue,
          currency: chartValues.first.currency?.value,
        ),
    ];
    final chartColors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.secondary,
      Theme.of(context).colorScheme.tertiary,
      context.colors.interactive,
      Theme.of(context).colorScheme.error,
    ];
    return ButlerlyCard(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              context.l10n.text('spendingDistribution'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: ButlerlySpacing.small),
          Semantics(
            label:
                '${context.l10n.text('spendingDistribution')}: ${chartSlices.map((slice) => '${slice.label} ${_sliceMoney(context, slice)}').join(', ')}',
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: CustomPaint(
                painter: _SpendingDonutPainter(
                  values: chartSlices.map((slice) => slice.value).toList(),
                  colors: chartColors,
                ),
              ),
            ),
          ),
          for (var index = 0; index < chartSlices.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: ButlerlySpacing.micro),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 8,
                    color: chartColors[index % chartColors.length],
                  ),
                  const SizedBox(width: ButlerlySpacing.micro),
                  Expanded(child: Text(chartSlices[index].label)),
                ],
              ),
            ),
          const SizedBox(height: ButlerlySpacing.small),
          for (final metric in model.categories.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: ButlerlySpacing.small),
              child: Semantics(
                label:
                    '${analysisDimension(context, metric, masterData)}, ${analysisMoney(context, metric)}',
                button: onCategoryTap != null,
                child: InkWell(
                  onTap: onCategoryTap == null
                      ? null
                      : () => onCategoryTap!(metric),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              analysisDimension(context, metric, masterData),
                            ),
                          ),
                          Text(analysisMoney(context, metric)),
                        ],
                      ),
                      const SizedBox(height: ButlerlySpacing.micro),
                      LinearProgressIndicator(
                        value: max == 0 ? 0 : analysisNumber(metric) / max,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (onViewAll != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onViewAll,
                child: Text(context.l10n.text('viewAllCategories')),
              ),
            ),
        ],
      ),
    );
  }
}

class _SpendingDonutPainter extends CustomPainter {
  const _SpendingDonutPainter({required this.values, required this.colors});
  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 12;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28;
    var start = -3.141592653589793 / 2;
    for (var index = 0; index < values.length; index++) {
      final sweep = values[index] / total * 2 * 3.141592653589793;
      paint.color = colors[index % colors.length];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _SpendingDonutPainter old) =>
      old.values != values || old.colors != colors;
}

class _SpendingSlice {
  const _SpendingSlice({
    required this.label,
    required this.value,
    required this.currency,
  });

  final String label;
  final double value;
  final String? currency;
}

String _sliceMoney(BuildContext context, _SpendingSlice slice) =>
    '${localizedDecimal(context, slice.value.toString())} ${slice.currency ?? ''}'
        .trim();
