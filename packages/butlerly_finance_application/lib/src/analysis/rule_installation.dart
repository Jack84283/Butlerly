import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import 'rule_loader.dart';

final class RuleInstallationResult {
  const RuleInstallationResult({
    required this.installed,
    required this.diagnostics,
  });
  final List<AnalysisRuleDefinition> installed;
  final Map<String, List<RuleDiagnostic>> diagnostics;
}

final class InstallBuiltInRules {
  const InstallBuiltInRules(
    this.repository, {
    this.parser = const RestrictedRuleParser(),
    this.validator = const RuleDefinitionValidator(),
  });
  final AnalysisRuleRepository repository;
  final RestrictedRuleParser parser;
  final RuleDefinitionValidator validator;

  Future<RuleInstallationResult> call(Map<String, String> sourceByPath) async {
    final installed = <AnalysisRuleDefinition>[];
    final diagnostics = <String, List<RuleDiagnostic>>{};
    final parsedDefinitions = <AnalysisRuleDefinition>[];
    final canonicalById = <String, String>{};
    for (final entry in sourceByPath.entries) {
      final parsed = parser.parse(entry.value);
      if (!parsed.isValid) {
        diagnostics[entry.key] = parsed.diagnostics;
        continue;
      }
      final result = validator.validate(parsed.document!);
      if (result.definition == null) {
        diagnostics[entry.key] = result.diagnostics;
        continue;
      }
      parsedDefinitions.add(result.definition!);
      canonicalById[result.definition!.identity.value] = canonicalize(
        parsed.document!.values,
      );
    }
    final ids = parsedDefinitions.map((value) => value.identity.value).toSet();
    for (final definition in parsedDefinitions) {
      final missing = definition.dependencies
          .where((value) => !ids.contains(value.ruleId.value))
          .toList(growable: false);
      if (missing.isNotEmpty) {
        diagnostics[definition.identity.value] = [
          RuleDiagnostic(
            code: 'missingDependency',
            message:
                'Rule depends on an unavailable definition: ${missing.first.ruleId.value}.',
          ),
        ];
        continue;
      }
      await repository.install(
        definition,
        sourceType: 'bundled',
        canonicalDefinition: canonicalById[definition.identity.value]!,
      );
      await repository.activate(
        definition.identity,
        definition.version,
        definition.enabled,
        DateTime.now().toUtc(),
      );
      installed.add(definition);
    }
    return RuleInstallationResult(
      installed: installed,
      diagnostics: diagnostics,
    );
  }
}
