import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

final class RuleDiagnostic {
  const RuleDiagnostic({required this.code, required this.message, this.field});
  final String code;
  final String message;
  final String? field;
}

final class ParsedRuleDocument {
  const ParsedRuleDocument(this.values);
  final Map<String, Object?> values;
}

final class RuleParseResult {
  const RuleParseResult({this.document, this.diagnostics = const []});
  final ParsedRuleDocument? document;
  final List<RuleDiagnostic> diagnostics;
  bool get isValid => document != null && diagnostics.isEmpty;
}

final class RestrictedRuleParser {
  const RestrictedRuleParser();

  RuleParseResult parse(String source) {
    final diagnostics = <RuleDiagnostic>[];
    if (RegExp(r'^---\s*$', multiLine: true).allMatches(source).length > 1 ||
        RegExp(r'^\.\.\.\s*$', multiLine: true).hasMatch(source)) {
      diagnostics.add(
        const RuleDiagnostic(
          code: 'multipleDocuments',
          message: 'Only one YAML document is allowed.',
        ),
      );
    }
    if (RegExp(r'(^|\s)[&*!]|(^|\s)<<\s*:', multiLine: true).hasMatch(source)) {
      diagnostics.add(
        const RuleDiagnostic(
          code: 'unsupportedYamlFeature',
          message:
              'Anchors, aliases, merge keys and custom tags are not allowed.',
        ),
      );
    }
    final keys = <String>{};
    for (final line in source.split('\n')) {
      final match = RegExp(
        r'^\s{0,2}([A-Za-z][A-Za-z0-9_]*)\s*:',
      ).firstMatch(line);
      if (match != null && !keys.add(match.group(1)!)) {
        diagnostics.add(
          RuleDiagnostic(
            code: 'duplicateKey',
            message: 'Duplicate YAML key: ${match.group(1)}.',
            field: match.group(1),
          ),
        );
      }
    }
    try {
      final value = loadYaml(source);
      if (value is! YamlMap) {
        diagnostics.add(
          const RuleDiagnostic(
            code: 'rootType',
            message: 'Rule YAML root must be a mapping.',
          ),
        );
      } else {
        final map = _toDart(value);
        if (map is! Map<String, Object?>) {
          diagnostics.add(
            const RuleDiagnostic(
              code: 'rootType',
              message: 'Rule YAML root must be a string-keyed mapping.',
            ),
          );
        } else {
          return diagnostics.isEmpty
              ? RuleParseResult(document: ParsedRuleDocument(map))
              : RuleParseResult(diagnostics: diagnostics);
        }
      }
    } on Object catch (error) {
      diagnostics.add(
        RuleDiagnostic(code: 'yamlSyntax', message: error.toString()),
      );
    }
    return RuleParseResult(diagnostics: diagnostics);
  }

  Object? _toDart(Object? value) {
    if (value is YamlMap) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _toDart(entry.value),
      };
    }
    if (value is YamlList) return value.map(_toDart).toList(growable: false);
    if (value is num && !value.isFinite) {
      throw const FormatException('Non-finite numbers are not allowed.');
    }
    if (value is DateTime) {
      throw const FormatException('Implicit timestamps are not allowed.');
    }
    return value;
  }
}

final class RuleDefinitionValidator {
  const RuleDefinitionValidator();

  ({AnalysisRuleDefinition? definition, List<RuleDiagnostic> diagnostics})
  validate(ParsedRuleDocument document) {
    final values = document.values;
    final diagnostics = <RuleDiagnostic>[];
    const supported = {
      'schemaVersion',
      'ruleId',
      'ruleVersion',
      'enabled',
      'type',
      'nameKey',
      'descriptionKey',
      'period',
      'measure',
      'grouping',
      'baseline',
      'condition',
      'severity',
      'dependencies',
      'filters',
    };
    for (final key in values.keys) {
      if (!supported.contains(key)) {
        diagnostics.add(
          RuleDiagnostic(
            code: 'unknownField',
            message: 'Unsupported rule field: $key.',
            field: key,
          ),
        );
      }
    }
    T? read<T>(String key) {
      final value = values[key];
      if (value is! T) {
        diagnostics.add(
          RuleDiagnostic(
            code: 'type',
            message: 'Field $key has an invalid type.',
            field: key,
          ),
        );
      }
      return value is T ? value : null;
    }

    final id = read<String>('ruleId');
    final version = read<String>('ruleVersion');
    final schema = read<String>('schemaVersion');
    final type = read<String>('type');
    final nameKey = read<String>('nameKey');
    final descriptionKey = read<String>('descriptionKey');
    final period = read<String>('period');
    final enabled = read<bool>('enabled');
    final measure = values['measure'];
    if (measure is! Map) {
      diagnostics.add(
        const RuleDiagnostic(
          code: 'required',
          message: 'Field measure is required.',
          field: 'measure',
        ),
      );
    }
    if (schema != null && schema != '1.0.0') {
      diagnostics.add(
        const RuleDiagnostic(
          code: 'schemaVersion',
          message: 'Unsupported rule schema version.',
          field: 'schemaVersion',
        ),
      );
    }
    if (nameKey != null && !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(nameKey)) {
      diagnostics.add(
        const RuleDiagnostic(
          code: 'localizationKey',
          message: 'Invalid localization key.',
          field: 'nameKey',
        ),
      );
    }
    if (descriptionKey != null &&
        !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(descriptionKey)) {
      diagnostics.add(
        const RuleDiagnostic(
          code: 'localizationKey',
          message: 'Invalid localization key.',
          field: 'descriptionKey',
        ),
      );
    }
    if (period != null &&
        period != 'selected_period' &&
        period != 'selected_month') {
      diagnostics.add(
        RuleDiagnostic(
          code: 'unsupportedPeriodType',
          message: 'Unsupported primary period type: $period.',
          field: 'period',
        ),
      );
    }
    for (final field in <String, Object?>{
      'schemaVersion': schema,
      'ruleId': id,
      'ruleVersion': version,
      'enabled': enabled,
      'type': type,
      'nameKey': nameKey,
      'descriptionKey': descriptionKey,
      'period': period,
    }.entries) {
      if (field.value == null) {
        diagnostics.add(
          RuleDiagnostic(
            code: 'required',
            message: 'Field ${field.key} is required.',
            field: field.key,
          ),
        );
      }
    }
    AnalysisRuleDefinition? definition;
    try {
      final operation = (measure as Map?)?['operation'] as String?;
      final field = (measure)?['field'] as String?;
      if (operation == null || field == null) {
        throw const FormatException('Measure requires operation and field.');
      }
      final operationValue = RuleOperation.values.byName(operation);
      final groupingValue = RuleGrouping.values.byName(
        values['grouping'] as String? ?? 'none',
      );
      final typeValue = AnalysisRuleType.values.byName(type ?? '');
      if (operationValue == RuleOperation.sum && field != 'amount') {
        throw const FormatException('Only amount can be summed.');
      }
      if (operationValue == RuleOperation.difference &&
          typeValue != AnalysisRuleType.metric) {
        throw const FormatException('Difference is only valid for metrics.');
      }
      if (groupingValue != RuleGrouping.none &&
          operationValue == RuleOperation.difference) {
        throw const FormatException(
          'Difference cannot be combined with grouping.',
        );
      }
      final canonical = canonicalize(values);
      final hash = RuleDefinitionHash(
        sha256.convert(utf8.encode(canonical)).toString(),
      );
      final grouping = groupingValue;
      final baseline = RuleBaseline.values.byName(
        values['baseline'] as String? ?? 'none',
      );
      final severity = RuleSeverity.values.byName(
        values['severity'] as String? ?? 'info',
      );
      final filters = <AnalysisFilter>[];
      final rawFilters = values['filters'];
      if (rawFilters is Map) {
        for (final entry in rawFilters.entries) {
          final kind = AnalysisFilterKind.values.byName(entry.key.toString());
          final rawValues = entry.value is List
              ? (entry.value as List)
                    .map((value) => value.toString())
                    .toList(growable: false)
              : [entry.value.toString()];
          filters.add(AnalysisFilter(kind: kind, values: rawValues));
        }
      }
      final dependencies = <RuleDependency>[];
      final rawDependencies = values['dependencies'];
      if (rawDependencies is List) {
        for (final value in rawDependencies) {
          dependencies.add(
            RuleDependency(ruleId: RuleIdentity(value.toString())),
          );
        }
      }
      final condition = _condition(values['condition']);
      definition = AnalysisRuleDefinition(
        identity: RuleIdentity(id ?? ''),
        version: RuleVersion(version ?? ''),
        schemaVersion: schema ?? '',
        type: AnalysisRuleType.values.byName(type ?? ''),
        nameKey: nameKey ?? '',
        descriptionKey: descriptionKey ?? '',
        enabled: enabled ?? false,
        status: AnalysisRuleStatus.active,
        period: period ?? 'currentPeriod',
        measure: RuleMeasure(
          operation: RuleOperation.values.byName(operation),
          field: field,
          currencyBasis: CurrencyBasis.values.byName(
            (measure as Map)['currencyBasis'] as String? ?? 'original',
          ),
        ),
        grouping: grouping,
        baseline: baseline,
        condition: condition,
        severity: severity,
        dependencies: dependencies,
        filters: filters,
        definitionHash: hash,
      );
    } on Object catch (error) {
      diagnostics.add(
        RuleDiagnostic(code: 'semantic', message: error.toString()),
      );
    }
    return (
      definition: diagnostics.isEmpty ? definition : null,
      diagnostics: diagnostics,
    );
  }
}

RuleCondition _condition(Object? raw) {
  if (raw is! Map) return const RuleCondition(operator: 'none');
  final children = raw['children'] is List
      ? (raw['children'] as List).map(_condition).toList(growable: false)
      : const <RuleCondition>[];
  final value = raw['value'];
  return RuleCondition(
    operator: raw['operator']?.toString() ?? 'none',
    value: value == null ? null : DecimalValue.parse(value.toString()),
    left: raw['left']?.toString(),
    right: raw['right']?.toString(),
    children: children,
  );
}

String canonicalize(Map<String, Object?> values) =>
    jsonEncode(_canonicalValue(values));
Object? _canonicalValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _canonicalValue(value[key])};
  }
  if (value is List) return value.map(_canonicalValue).toList(growable: false);
  return value;
}
