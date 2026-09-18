import 'dart:math' as math;

import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

enum ButlerlyVisualizationDensity { compact, regular }

abstract final class ButlerlyVisualizationTokens {
  static const compactChartHeight = 96.0;
  static const regularChartHeight = 160.0;
  static const compactDonutSize = 96.0;
  static const regularDonutSize = 144.0;
  static const horizontalLabelWidth = 76.0;
  static const horizontalValueMinWidth = 72.0;
  static const horizontalTrackHeight = 8.0;
  static const signedTrackHeight = 12.0;
  static const trendAxisWidth = 1.0;
  static const trendStrokeWidth = 2.0;
  static const trendPointRadius = 4.0;
  static const donutStrokeRatio = 0.22;
  static const legendMarkerSize = 10.0;
  static const narrowLayoutWidth = 360.0;
}

final class ButlerlyChartDatum {
  const ButlerlyChartDatum({
    required this.label,
    required this.value,
    this.color,
    this.valueLabel,
  });

  final String label;
  final double value;
  final Color? color;
  final String? valueLabel;
}

class ButlerlyHorizontalValueRow extends StatelessWidget {
  const ButlerlyHorizontalValueRow({
    super.key,
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
      final stacked =
          constraints.maxWidth <
              ButlerlyVisualizationTokens.narrowLayoutWidth ||
          largeText;
      final track = ClipRRect(
        borderRadius: BorderRadius.circular(ButlerlyRadius.small),
        child: LinearProgressIndicator(
          value: fraction.clamp(0.0, 1.0).toDouble(),
          minHeight: ButlerlyVisualizationTokens.horizontalTrackHeight,
          backgroundColor: context.colors.subtleSurface,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );

      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                const SizedBox(width: ButlerlySpacing.compact),
                Flexible(
                  child: Text(
                    valueLabel,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ButlerlySpacing.micro),
            track,
          ],
        );
      }

      return Row(
        children: [
          SizedBox(
            width: ButlerlyVisualizationTokens.horizontalLabelWidth,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(child: track),
          const SizedBox(width: ButlerlySpacing.small),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: ButlerlyVisualizationTokens.horizontalValueMinWidth,
            ),
            child: Text(
              valueLabel,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      );
    },
  );
}

class ButlerlySignedHorizontalValueRow extends StatelessWidget {
  const ButlerlySignedHorizontalValueRow({
    super.key,
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
    final track = SizedBox(
      height: ButlerlyVisualizationTokens.signedTrackHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final half = constraints.maxWidth / 2;
          final width = half * fraction;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: ButlerlyVisualizationTokens.horizontalTrackHeight,
                decoration: BoxDecoration(
                  color: context.colors.subtleSurface,
                  borderRadius: BorderRadius.circular(ButlerlyRadius.small),
                ),
              ),
              Positioned(
                left: half,
                top: 0,
                bottom: 0,
                child: Container(
                  width: ButlerlyVisualizationTokens.trendAxisWidth,
                  color: context.colors.secondaryText,
                ),
              ),
              Positioned(
                left: value < 0 ? half - width : half,
                width: width,
                top: ButlerlySpacing.xxs,
                bottom: ButlerlySpacing.xxs,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(ButlerlyRadius.small),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
        final stacked =
            constraints.maxWidth <
                ButlerlyVisualizationTokens.narrowLayoutWidth ||
            largeText;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(width: ButlerlySpacing.compact),
                  Flexible(
                    child: Text(
                      valueLabel,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ButlerlySpacing.micro),
              track,
            ],
          );
        }
        return Row(
          children: [
            SizedBox(
              width: ButlerlyVisualizationTokens.horizontalLabelWidth,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(child: track),
            const SizedBox(width: ButlerlySpacing.small),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: ButlerlyVisualizationTokens.horizontalValueMinWidth,
              ),
              child: Text(
                valueLabel,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        );
      },
    );
  }
}

class ButlerlyDonutVisualization extends StatelessWidget {
  const ButlerlyDonutVisualization({
    super.key,
    required this.data,
    required this.valueLabel,
    this.density = ButlerlyVisualizationDensity.compact,
    this.legendBelow = false,
    this.onDatumTap,
  });

  final List<ButlerlyChartDatum> data;
  final String Function(double value, double total) valueLabel;
  final ButlerlyVisualizationDensity density;
  final bool legendBelow;
  final ValueChanged<ButlerlyChartDatum>? onDatumTap;

  @override
  Widget build(BuildContext context) {
    final usable = data.where((item) => item.value > 0).toList(growable: false);
    final total = usable.fold<double>(0, (sum, item) => sum + item.value);
    if (usable.isEmpty || total <= 0) return const SizedBox.shrink();

    final fallback = ButlerlyChartColors.categoryPalette;
    final colors = [
      for (var index = 0; index < usable.length; index++)
        usable[index].color ?? fallback[index % fallback.length],
    ];
    final size = switch (density) {
      ButlerlyVisualizationDensity.compact =>
        ButlerlyVisualizationTokens.compactDonutSize,
      ButlerlyVisualizationDensity.regular =>
        ButlerlyVisualizationTokens.regularDonutSize,
    };
    final semanticLabel = usable
        .map(
          (item) =>
              '${item.label}: ${item.valueLabel ?? valueLabel(item.value, total)}',
        )
        .join(', ');

    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
            final stacked =
                legendBelow ||
                constraints.maxWidth <
                    ButlerlyVisualizationTokens.narrowLayoutWidth ||
                largeText;
            final chart = SizedBox.square(
              dimension: size,
              child: CustomPaint(
                painter: _ButlerlyDonutPainter(
                  values: usable.map((item) => item.value).toList(),
                  colors: colors,
                ),
              ),
            );
            final legend = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < usable.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: ButlerlySpacing.micro,
                    ),
                    child: InkWell(
                      onTap: onDatumTap == null
                          ? null
                          : () => onDatumTap!(usable[index]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: ButlerlySpacing.xxs,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width:
                                  ButlerlyVisualizationTokens.legendMarkerSize,
                              height:
                                  ButlerlyVisualizationTokens.legendMarkerSize,
                              decoration: BoxDecoration(
                                color: colors[index],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: ButlerlySpacing.compact),
                            Expanded(child: Text(usable[index].label)),
                            const SizedBox(width: ButlerlySpacing.compact),
                            Text(
                              usable[index].valueLabel ??
                                  valueLabel(usable[index].value, total),
                              textAlign: TextAlign.end,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );

            if (stacked) {
              return Column(
                children: [
                  chart,
                  const SizedBox(height: ButlerlySpacing.standard),
                  legend,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                chart,
                const SizedBox(width: ButlerlySpacing.standard),
                Expanded(child: legend),
              ],
            );
          },
        ),
      ),
    );
  }
}

class ButlerlyTrendVisualization extends StatelessWidget {
  const ButlerlyTrendVisualization({
    super.key,
    required this.data,
    required this.valueLabel,
    this.lineColor,
    this.showLabels = false,
    this.density = ButlerlyVisualizationDensity.compact,
  });

  final List<ButlerlyChartDatum> data;
  final String Function(double value) valueLabel;
  final Color? lineColor;
  final bool showLabels;
  final ButlerlyVisualizationDensity density;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final height = switch (density) {
      ButlerlyVisualizationDensity.compact =>
        ButlerlyVisualizationTokens.compactChartHeight,
      ButlerlyVisualizationDensity.regular =>
        ButlerlyVisualizationTokens.regularChartHeight,
    };
    return Semantics(
      label: data
          .map(
            (item) =>
                '${item.label}: ${item.valueLabel ?? valueLabel(item.value)}',
          )
          .join(', '),
      child: ExcludeSemantics(
        child: Column(
          children: [
            SizedBox(
              height: height,
              width: double.infinity,
              child: CustomPaint(
                painter: _ButlerlyTrendPainter(
                  values: data
                      .map((item) => item.value)
                      .toList(growable: false),
                  lineColor: lineColor ?? context.colors.info,
                  axisColor: context.colors.cardDivider,
                  showPoints: density == ButlerlyVisualizationDensity.regular,
                ),
              ),
            ),
            if (showLabels) ...[
              const SizedBox(height: ButlerlySpacing.compact),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final item in data)
                    Flexible(
                      child: Text(
                        item.label,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.fade,
                        maxLines: 2,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ButlerlyDonutPainter extends CustomPainter {
  const _ButlerlyDonutPainter({required this.values, required this.colors});

  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;
    final rect = Offset.zero & size;
    final strokeWidth =
        size.shortestSide * ButlerlyVisualizationTokens.donutStrokeRatio;
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
  bool shouldRepaint(covariant _ButlerlyDonutPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors;
}

class _ButlerlyTrendPainter extends CustomPainter {
  const _ButlerlyTrendPainter({
    required this.values,
    required this.lineColor,
    required this.axisColor,
    required this.showPoints,
  });

  final List<double> values;
  final Color lineColor;
  final Color axisColor;
  final bool showPoints;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final range = maxValue == minValue ? 1.0 : maxValue - minValue;
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = ButlerlyVisualizationTokens.trendAxisWidth;
    canvas.drawLine(
      Offset(0, size.height - ButlerlyVisualizationTokens.trendAxisWidth),
      Offset(
        size.width,
        size.height - ButlerlyVisualizationTokens.trendAxisWidth,
      ),
      axisPaint,
    );

    final path = Path();
    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * index / (values.length - 1);
      final normalized = (values[index] - minValue) / range;
      final verticalInset = ButlerlySpacing.compact;
      final y =
          size.height -
          verticalInset -
          normalized * (size.height - verticalInset * 2);
      final point = Offset(x, y);
      points.add(point);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    if (values.length > 1) {
      canvas.drawPath(
        path,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = ButlerlyVisualizationTokens.trendStrokeWidth,
      );
    }
    if (showPoints) {
      final pointPaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.fill;
      for (final point in points) {
        canvas.drawCircle(
          point,
          ButlerlyVisualizationTokens.trendPointRadius,
          pointPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ButlerlyTrendPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.axisColor != axisColor ||
      oldDelegate.showPoints != showPoints;
}
