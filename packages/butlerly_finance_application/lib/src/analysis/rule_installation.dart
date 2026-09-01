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
    this.catalogValidator = const RuleCatalogValidator(),
  });
  final AnalysisRuleRepository repository;
  final RestrictedRuleParser parser;
  final RuleDefinitionValidator validator;
  final RuleCatalogValidator catalogValidator;

  Future<RuleInstallationResult> call(
    Map<String, String> sourceByPath, {
    String? catalogSource,
  }) async {
    final installed = <AnalysisRuleDefinition>[];
    final diagnostics = <String, List<RuleDiagnostic>>{};
    final parsedDefinitions = <AnalysisRuleDefinition>[];
    final canonicalById = <String, String>{};
    final pathsById = <String, String>{};
    final definitionsByPath = <String, AnalysisRuleDefinition>{};
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
      final id = result.definition!.identity.value;
      final previousPath = pathsById[id];
      if (previousPath != null) {
        diagnostics[entry.key] = [
          RuleDiagnostic(
            code: 'duplicateRuleId',
            message: 'Rule ID $id is already defined by $previousPath.',
          ),
        ];
        continue;
      }
      parsedDefinitions.add(result.definition!);
      pathsById[id] = entry.key;
      definitionsByPath[entry.key] = result.definition!;
      canonicalById[id] = canonicalize(parsed.document!.values);
    }
    if (catalogSource != null) {
      final catalogDiagnostics = catalogValidator.validate(
        source: catalogSource,
        definitionsByPath: definitionsByPath,
      );
      if (catalogDiagnostics.isNotEmpty) {
        diagnostics['catalog.yaml'] = catalogDiagnostics;
        return RuleInstallationResult(
          installed: const [],
          diagnostics: diagnostics,
        );
      }
    }
    final ids = parsedDefinitions.map((value) => value.identity.value).toSet();
    final byId = {
      for (final value in parsedDefinitions) value.identity.value: value,
    };
    final visiting = <String>{};
    final visited = <String>{};
    final cyclic = <String>{};
    void visit(AnalysisRuleDefinition definition) {
      if (visited.contains(definition.identity.value)) return;
      if (!visiting.add(definition.identity.value)) {
        cyclic.add(definition.identity.value);
        return;
      }
      for (final dependency in definition.dependencies) {
        final target = byId[dependency.ruleId.value];
        if (target != null) visit(target);
      }
      visiting.remove(definition.identity.value);
      visited.add(definition.identity.value);
    }

    for (final definition in parsedDefinitions) {
      visit(definition);
    }
    for (final definition in parsedDefinitions) {
      final missing = definition.dependencies
          .where((value) => !ids.contains(value.ruleId.value))
          .toList(growable: false);
      final versions = <String, RuleVersion>{
        for (final value in parsedDefinitions)
          value.identity.value: value.version,
      };
      final incompatible = definition.dependencies
          .where(
            (value) =>
                value.minimumVersion != null &&
                versions[value.ruleId.value] != null &&
                _compareVersions(
                      versions[value.ruleId.value]!,
                      value.minimumVersion!,
                    ) <
                    0,
          )
          .toList(growable: false);
      if (missing.isNotEmpty ||
          incompatible.isNotEmpty ||
          cyclic.contains(definition.identity.value)) {
        diagnostics[definition.identity.value] = [
          RuleDiagnostic(
            code: missing.isNotEmpty
                ? 'missingDependency'
                : incompatible.isNotEmpty
                ? 'dependencyVersion'
                : 'dependencyCycle',
            message: missing.isNotEmpty
                ? 'Rule depends on an unavailable definition: ${missing.first.ruleId.value}.'
                : incompatible.isNotEmpty
                ? 'Rule requires ${incompatible.first.ruleId.value}@${incompatible.first.minimumVersion!.value}.'
                : 'Rule participates in a dependency cycle.',
          ),
        ];
        continue;
      }
      await repository.install(
        definition,
        sourceType: 'bundled',
        canonicalDefinition: canonicalById[definition.identity.value]!,
      );
      final existing = await repository.existingActivation(definition.identity);
      if (existing == null || existing.version != definition.version) {
        await repository.activate(
          definition.identity,
          definition.version,
          existing?.enabled ?? definition.enabled,
          DateTime.now().toUtc(),
        );
      }
      installed.add(definition);
    }
    return RuleInstallationResult(
      installed: installed,
      diagnostics: diagnostics,
    );
  }
}

int _compareVersions(RuleVersion left, RuleVersion right) {
  final a = left.value.split('.').map(int.parse).toList(growable: false);
  final b = right.value.split('.').map(int.parse).toList(growable: false);
  for (var i = 0; i < 3; i++) {
    final comparison = a[i].compareTo(b[i]);
    if (comparison != 0) return comparison;
  }
  return 0;
}
