import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/features/analysis/presentation/analysis_formatters.dart';
import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class AnalysisTrend extends StatelessWidget {
  const AnalysisTrend({
    super.key,
    required this.model,
    required this.masterData,
  });
  final AnalysisModel model;
  final TransactionMasterData? masterData;

  @override
  Widget build(BuildContext context) {
    if (model.trend.isEmpty) {
      return ButlerlyCard(
        child: Text(context.l10n.text('insufficientTrendData')),
      );
    }
    final max = model.trend
        .map(analysisNumber)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return ButlerlyCard(
      semanticLabel: context.l10n.text('spendingTrend'),
      child: Semantics(
        label: model.trend
            .map(
              (m) =>
                  '${analysisDimension(context, m, masterData)} ${analysisMoney(context, m)}',
            )
            .join(', '),
        child: SizedBox(
          height: 150,
          child: CustomPaint(
            painter: _TrendPainter(
              values: model.trend
                  .map<double>((m) => max == 0 ? 0 : analysisNumber(m) / max)
                  .toList(),
              color: context.colors.interactive,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.values, required this.color});
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final y =
          size.height - (size.height * values[i]).clamp(8, size.height - 8);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    if (values.length > 1) canvas.drawPath(path, paint);
    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final y =
          size.height - (size.height * values[i]).clamp(8, size.height - 8);
      canvas.drawCircle(Offset(x, y), 5, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.values != values || old.color != color;
}
