import 'dart:io';

import 'package:butlerly/core/analysis/bundled_analysis_rules.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late LocalDatabase database;

  LocalDatabase createDatabase() => LocalDatabase(
    logger: AppLogger(),
    factory: databaseFactoryFfi,
    databaseDirectory: directory.path,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'butlerly_bundled_rules_',
    );
    database = createDatabase();
    await database.initialize();
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'startup assets install the complete catalog and survive reload',
    () async {
      var repository = SqliteAnalysisRuleRepository(
        database.persistenceDatabase,
      );
      final result = await installBundledAnalysisRules(
        InstallBuiltInRules(repository),
      );
      expect(result.diagnostics, isEmpty);
      expect(result.installed, hasLength(22));
      final expected = {
        for (final rule in result.installed)
          rule.identity.value:
              '${rule.version.value}:${rule.definitionHash.value}',
      };
      expect(expected.keys, containsAll(['ANL-R027', 'ANL-R028', 'ANL-R029']));
      final definitionsBefore = await database.database.query(
        'analysis_rule_definitions',
      );
      final activationsBefore = await database.database.query(
        'analysis_rule_activations',
      );

      await database.close();
      database = createDatabase();
      await database.initialize();
      repository = SqliteAnalysisRuleRepository(database.persistenceDatabase);
      final reloaded = await repository.listActive();
      expect({
        for (final rule in reloaded)
          rule.identity.value:
              '${rule.version.value}:${rule.definitionHash.value}',
      }, expected);

      final repeated = await installBundledAnalysisRules(
        InstallBuiltInRules(repository),
      );
      expect(repeated.diagnostics, isEmpty);
      expect(
        await database.database.query('analysis_rule_definitions'),
        definitionsBefore,
      );
      expect(
        await database.database.query('analysis_rule_activations'),
        activationsBefore,
      );
    },
  );

  test(
    'missing packaged catalog definition is diagnosed before installation',
    () async {
      final repository = SqliteAnalysisRuleRepository(
        database.persistenceDatabase,
      );
      final result = await installBundledAnalysisRules(
        InstallBuiltInRules(repository),
        bundle: _MissingRuleBundle(),
      );
      expect(result.installed, isEmpty);
      expect(
        result.diagnostics['catalog.yaml'],
        contains(
          isA<RuleDiagnostic>().having(
            (value) => value.code,
            'code',
            'catalogMissingFile',
          ),
        ),
      );
      expect(await repository.listDefinitions(), isEmpty);
    },
  );

  test('transactional rule repair rolls back partial installation', () async {
    final repository = SqliteAnalysisRuleRepository(
      database.persistenceDatabase,
    );
    final original = await rootBundle.loadString(
      'assets/analysis_rules/metrics/ANL-R001.yaml',
    );
    final conflicting = original.replaceFirst(
      'descriptionKey: analysis.rule.r001.description',
      'descriptionKey: analysis.rule.r001.conflicting',
    );
    final parsed = const RestrictedRuleParser().parse(conflicting);
    final validation = const RuleDefinitionValidator().validate(
      parsed.document!,
    );
    final definition = validation.definition!;
    await repository.install(
      definition,
      sourceType: 'bundled',
      canonicalDefinition: canonicalize(parsed.document!.values),
    );

    final second = await rootBundle.loadString(
      'assets/analysis_rules/metrics/ANL-R002.yaml',
    );
    await expectLater(
      repository.transaction(
        (transactionRepository) => InstallBuiltInRules(transactionRepository)({
          'metrics/ANL-R002.yaml': second,
          'metrics/ANL-R001.yaml': original,
        }),
      ),
      throwsA(isA<StateError>()),
    );
    expect(await repository.listDefinitions(), hasLength(1));
    expect(
      (await repository.listDefinitions()).single.identity.value,
      'ANL-R001',
    );
  });

  test(
    'does not replace a missing custom rule with a colliding bundled rule',
    () async {
      final repository = SqliteAnalysisRuleRepository(
        database.persistenceDatabase,
      );
      final bundled = await rootBundle.loadString(
        'assets/analysis_rules/metrics/ANL-R010.yaml',
      );
      final custom = bundled.replaceFirst(
        'descriptionKey: analysis.rule.r010.description',
        'descriptionKey: custom.rule.r010.description',
      );
      final parsed = const RestrictedRuleParser().parse(custom);
      final validation = const RuleDefinitionValidator().validate(
        parsed.document!,
      );
      final customDefinition = validation.definition!;
      await repository.install(
        customDefinition,
        sourceType: 'user',
        canonicalDefinition: canonicalize(parsed.document!.values),
      );
      await repository.activate(
        customDefinition.identity,
        customDefinition.version,
        true,
        DateTime.utc(2026, 11, 1),
      );
      await database.database.insert('analysis_rule_configurations', {
        'rule_id': customDefinition.identity.value,
        'configuration': '{"custom":true}',
        'updated_at': '2026-11-01T00:00:00.000Z',
      });
      await database.database.delete(
        'analysis_rule_definitions',
        where: 'rule_id = ? AND rule_version = ?',
        whereArgs: [
          customDefinition.identity.value,
          customDefinition.version.value,
        ],
      );

      await expectLater(
        repository.transaction(
          (transactionRepository) => InstallBuiltInRules(transactionRepository)(
            {'metrics/ANL-R010.yaml': bundled},
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        await database.database.query(
          'analysis_rule_definitions',
          where: 'rule_id = ? AND rule_version = ?',
          whereArgs: [
            customDefinition.identity.value,
            customDefinition.version.value,
          ],
        ),
        isEmpty,
      );
      expect(
        (await database.database.query(
          'analysis_rule_provenance',
          where: 'rule_id = ? AND rule_version = ?',
          whereArgs: [
            customDefinition.identity.value,
            customDefinition.version.value,
          ],
        )).single,
        allOf(
          containsPair('source_type', 'user'),
          containsPair(
            'definition_hash',
            customDefinition.definitionHash.value,
          ),
        ),
      );
      expect(
        await database.database.query(
          'analysis_rule_activations',
          where: 'rule_id = ?',
          whereArgs: [customDefinition.identity.value],
        ),
        hasLength(1),
      );
      expect(
        await database.database.query(
          'analysis_rule_configurations',
          where: 'rule_id = ?',
          whereArgs: [customDefinition.identity.value],
        ),
        hasLength(1),
      );
    },
  );

  test('transactional rule repair rolls back installer diagnostics', () async {
    final repository = SqliteAnalysisRuleRepository(
      database.persistenceDatabase,
    );
    final valid = await rootBundle.loadString(
      'assets/analysis_rules/metrics/ANL-R002.yaml',
    );
    final missingDependency = valid
        .replaceFirst('ruleId: ANL-R002', 'ruleId: ANL-R999')
        .replaceFirst(
          'period: selected_period',
          'period: selected_period\n'
              'dependencies:\n'
              '  - ruleId: ANL-R998\n'
              '    minimumVersion: "1.0.0"',
        );

    await expectLater(
      repository.transaction((transactionRepository) async {
        final result = await InstallBuiltInRules(transactionRepository)({
          'metrics/ANL-R002.yaml': valid,
          'metrics/ANL-R999.yaml': missingDependency,
        });
        if (result.diagnostics.isNotEmpty) {
          throw StateError('Bundled analysis rules failed validation.');
        }
        return result;
      }),
      throwsA(isA<StateError>()),
    );
    expect(await repository.listDefinitions(), isEmpty);
  });
}

class _MissingRuleBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final data = await rootBundle.load(key);
    if (key != 'AssetManifest.bin') return data;
    const codec = StandardMessageCodec();
    final manifest = Map<Object?, Object?>.from(
      codec.decodeMessage(data)! as Map,
    );
    manifest.remove('assets/analysis_rules/insights/ANL-R029.yaml');
    return codec.encodeMessage(manifest)!;
  }
}
