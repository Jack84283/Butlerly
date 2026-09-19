import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

export 'package:butlerly_finance_application/butlerly_finance_application.dart'
    show AnalysisQualitySummary, analysisQualitySummary, isUsableComparison;

/// Compatibility name for widgets consuming the application-owned projection.
typedef AnalysisModel = AnalysisOverview;

double analysisNumber(AnalysisMetric metric) =>
    double.tryParse(metric.value.toString()) ?? 0;

String analysisCategoryId(AnalysisMetric metric) =>
    metric.dimension?.split(':').firstOrNull ?? '';

String analysisRawDimension(AnalysisMetric metric) =>
    metric.dimension?.split(':').firstOrNull ?? metric.rule.nameKey;

String analysisPeriodKey(AnalysisMetric metric) => analysisRawDimension(metric);
