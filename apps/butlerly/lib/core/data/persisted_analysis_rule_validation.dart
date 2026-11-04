import 'dart:convert';

import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:crypto/crypto.dart';

/// Validates a persisted analysis rule using the same semantic contract as an
/// imported rule document. Hash validation alone is not enough: a correctly
/// hashed JSON object can still be impossible to reconstruct into a rule.
bool isSemanticallyValidPersistedAnalysisRule(Map<String, Object?> row) {
  if (row['validation_status'] != 'valid') return false;
  final ruleId = row['rule_id'];
  final ruleVersion = row['rule_version'];
  final canonical = row['canonical_definition'];
  final expectedHash = row['definition_hash'];
  if (ruleId is! String ||
      ruleVersion is! String ||
      canonical is! String ||
      canonical.isEmpty ||
      expectedHash is! String ||
      expectedHash.isEmpty) {
    return false;
  }

  try {
    final decoded = jsonDecode(canonical);
    if (decoded is! Map) return false;
    final values = <String, Object?>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) return false;
      values[entry.key as String] = entry.value;
    }
    final validation = const RuleDefinitionValidator().validate(
      ParsedRuleDocument(values),
    );
    final definition = validation.definition;
    if (definition == null || validation.diagnostics.isNotEmpty) return false;
    if (definition.identity.value != ruleId ||
        definition.version.value != ruleVersion) {
      return false;
    }
    return sha256.convert(utf8.encode(canonical)).toString() == expectedHash;
  } on Object {
    return false;
  }
}
