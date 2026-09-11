import 'dart:math' as math;

import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

final class InsightChartDatum {
  const InsightChartDatum({required this.label, required this.value});

  final String label;
  final double value;
}

class InsightComparisonVisualization extends StatelessWidget {
  const InsightComparisonVisualization({
    super.key,
    required this.currentLabel,
    required this.baselineLabel,
    required this.currentValue,
    required this.baselineValue,
    required this.currentValueLabel,
    required this.baselineValueLabel,
    required this.semanticColor,
    this.signed = false,
  });

  final String currentLabel;
  final String baselineLabel;
  final double currentValue;
  final double baselineValue;
  final String currentValueLabel;
  final String baselineValueLabel;
  final Color semanticColor;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final maximum = math.max(currentValue.abs(), baselineValue.abs());
    final denominator = maximum == 0 ? 1.0 : maximum;
    return Semantics(
      label:
          '$baselineLabel $baselineValueLabel, $currentLabel $currentValueLabel',
      child: ExcludeSemantics(
        child: Column(
          children: [
            if (signed)
              _SignedComparisonRow(
                label: baselineLabel,
                valueLabel: baselineValueLabel,
                value: baselineValue,
                denominator: denominator,
                color: context.colors.secondaryText,
              )
            else
              _ComparisonRow(
                label: baselineLabel,
                valueLabel: baselineValueLabel,
                fraction: baselineValue.abs() / denominator,
                color: context.colors.secondaryText,
              ),
            const SizedBox(height: ButlerlySpacing.compact),
            if (signed)
              _SignedComparisonRow(
                label: currentLabel,
                valueLabel: currentValueLabel,
                value: currentValue,
                denominator: denominator,
                color: semanticColor,
              )
            else
              _ComparisonRow(
                label: currentLabel,
                valueLabel: currentValueLabel,
                fraction: currentValue.abs() / denominator,
                color: semanticColor,
              ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.label,
    required this.valueLabel,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String valueLabel;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 76,
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(ButlerlyRadius.small),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0).toDouble(),
            minHeight: 8,
            backgroundColor: context.colors.subtleSurface,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ),
      const SizedBox(width: ButlerlySpacing.small),
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 72),
        child: Text(
          valueLabel,
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    ],
  );
}

class _SignedComparisonRow extends StatelessWidget {
  const _SignedComparisonRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.denominator,
    required this.color,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double denominator;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = (value.abs() / denominator).clamp(0.0, 1.0).toDouble();
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(
          child: SizedBox(
            height: 12,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final half = constraints.maxWidth / 2;
                final width = half * fraction;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: context.colors.subtleSurface,
                        borderRadius: BorderRadius.circular(
                          ButlerlyRadius.small,
                        ),
                      ),
                    ),
                    Positioned(
                      left: half,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 1,
                        color: context.colors.secondaryText,
                      ),
                    ),
                    Positioned(
                      left: value < 0 ? half - width : half,
                      width: width,
                      top: 2,
                      bottom: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(
                            ButlerlyRadius.small,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(width: ButlerlySpacing.small),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 72),
          child: Text(
            valueLabel,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}

class InsightBarVisualization extends StatelessWidget {
  const InsightBarVisualization({
    super.key,
    required this.data,
    required this.valueLabel,
  });

  final List<InsightChartDatum> data;
  final String Function(double value) valueLabel;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final maximum = data.fold<double>(
      0,
      (maxValue, item) => math.max(maxValue, item.value.abs()),
    );
    final denominator = maximum == 0 ? 1.0 : maximum;
    return Column(
      children: [
        for (final item in data.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: ButlerlySpacing.compact),
            child: Semantics(
              label: '${item.label}: ${valueLabel(item.value)}',
              child: ExcludeSemantics(
                child: _ComparisonRow(
                  label: item.label,
                  valueLabel: valueLabel(item.value),
                  fraction: item.value.abs() / denominator,
                  color: context.colors.info,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class InsightDonutVisualization extends StatelessWidget {
  const InsightDonutVisualization({super.key, required this.data});

  final List<InsightChartDatum> data;

  @override
  Widget build(BuildContext context) {
    final usable = data.where((item) => item.value > 0).toList(growable: false);
    final total = usable.fold<double>(0, (sum, item) => sum + item.value);
    if (usable.length < 2 || total <= 0) return const SizedBox.shrink();
    final palette = <Color>[
      context.colors.info,
      context.colors.success,
      context.colors.warning,
      context.colors.brand,
      context.colors.secondaryText,
    ];
    return Semantics(
      label: usable
          .map(
            (item) =>
                '${item.label}: ${(item.value / total * 100).toStringAsFixed(1)}%',
          )
          .join(', '),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: CustomPaint(
                painter: _DonutPainter(
                  values: usable.map((item) => item.value).toList(),
                  colors: palette,
                ),
              ),
            ),
            const SizedBox(width: ButlerlySpacing.standard),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < usable.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: ButlerlySpacing.micro,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: palette[index % palette.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: ButlerlySpacing.compact),
                          Expanded(child: Text(usable[index].label)),
                          Text(
                            '${(usable[index].value / total * 100).toStringAsFixed(0)}%',
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InsightTrendVisualization extends StatelessWidget {
  const InsightTrendVisualization({
    super.key,
    required this.data,
    required this.valueLabel,
  });

  final List<InsightChartDatum> data;
  final String Function(double value) valueLabel;

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) return const SizedBox.shrink();
    return Semantics(
      label: data
          .map((item) => '${item.label}: ${valueLabel(item.value)}')
          .join(', '),
      child: ExcludeSemantics(
        child: SizedBox(
          height: 96,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendPainter(
              values: data.map((item) => item.value).toList(growable: false),
              lineColor: context.colors.info,
              axisColor: context.colors.cardDivider,
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.values, required this.colors});

  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;
    final rect = Offset.zero & size;
    final strokeWidth = size.shortestSide * 0.22;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;
    var start = -math.pi / 2;
    for (var index = 0; index < values.length; index++) {
      final sweep = values[index] / total * math.pi * 2;
      paint.color = colors[index % colors.length];
      canvas.drawArc(rect.deflate(strokeWidth / 2), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors;
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.values,
    required this.lineColor,
    required this.axisColor,
  });

  final List<double> values;
  final Color lineColor;
  final Color axisColor;

  @override
  void paint(Canvas canvas, Size size) {
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = maxValue == minValue ? 1.0 : maxValue - minValue;
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      axisPaint,
    );
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? 0.0
          : size.width * index / (values.length - 1);
      final normalized = (values[index] - minValue) / range;
      final y = size.height - 8 - normalized * (size.height - 16);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.axisColor != axisColor;
}
