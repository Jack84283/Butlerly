import 'dart:math' as math;

import 'package:butlerly/design_system/components/butlerly_visualization_primitives.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

typedef InsightChartDatum = ButlerlyChartDatum;

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
              ButlerlySignedHorizontalValueRow(
                label: baselineLabel,
                valueLabel: baselineValueLabel,
                value: baselineValue,
                denominator: denominator,
                color: context.colors.secondaryText,
              )
            else
              ButlerlyHorizontalValueRow(
                label: baselineLabel,
                valueLabel: baselineValueLabel,
                fraction: baselineValue.abs() / denominator,
                color: context.colors.secondaryText,
              ),
            const SizedBox(height: ButlerlySpacing.compact),
            if (signed)
              ButlerlySignedHorizontalValueRow(
                label: currentLabel,
                valueLabel: currentValueLabel,
                value: currentValue,
                denominator: denominator,
                color: semanticColor,
              )
            else
              ButlerlyHorizontalValueRow(
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
                child: ButlerlyHorizontalValueRow(
                  label: item.label,
                  valueLabel: valueLabel(item.value),
                  fraction: item.value.abs() / denominator,
                  color: item.color ?? context.colors.info,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class InsightDonutVisualization extends StatelessWidget {
  const InsightDonutVisualization({
    super.key,
    required this.data,
    required this.percentageLabel,
    this.density = ButlerlyVisualizationDensity.compact,
    this.legendBelow = false,
  });

  final List<InsightChartDatum> data;
  final String Function(double value) percentageLabel;
  final ButlerlyVisualizationDensity density;
  final bool legendBelow;

  @override
  Widget build(BuildContext context) => ButlerlyDonutVisualization(
    data: data,
    valueLabel: (value, total) => percentageLabel(value / total * 100),
    density: density,
    legendBelow: legendBelow,
  );
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
  Widget build(BuildContext context) => ButlerlyTrendVisualization(
    data: data,
    valueLabel: valueLabel,
    density: ButlerlyVisualizationDensity.compact,
  );
}
