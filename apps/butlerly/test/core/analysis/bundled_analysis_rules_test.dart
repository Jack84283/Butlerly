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
      expect(result.installed, hasLength(20));
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
