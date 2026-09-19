import 'dart:io';

import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('database catalog reseed is authoritative and idempotent', () async {
    final root = await Directory.systemTemp.createTemp(
      'butlerly-system-catalog-',
    );
    addTearDown(() => root.delete(recursive: true));
    final database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: root.path,
    );
    await database.initialize();
    addTearDown(database.close);

    await database.database.insert('tags', {
      'id': 'user.tag.keep',
      'name': 'Keep me',
      'status': 'active',
    });
    await database.database.update(
      'tags',
      {'status': 'archived'},
      where: 'id = ?',
      whereArgs: ['tag.recurring'],
    );
    await database.database.delete(
      'tags',
      where: 'id = ?',
      whereArgs: ['tag.subscription'],
    );
    await database.database.delete(
      'tag_translations',
      where: 'tag_id = ? AND locale = ?',
      whereArgs: ['tag.travel', 'es'],
    );

    await database.reseedSystemCatalog();

    final recurring = await database.database.query(
      'tags',
      where: 'id = ?',
      whereArgs: ['tag.recurring'],
    );
    final subscription = await database.database.query(
      'tags',
      where: 'id = ?',
      whereArgs: ['tag.subscription'],
    );
    final userTag = await database.database.query(
      'tags',
      where: 'id = ?',
      whereArgs: ['user.tag.keep'],
    );
    final translation = await database.database.query(
      'tag_translations',
      where: 'tag_id = ? AND locale = ?',
      whereArgs: ['tag.travel', 'es'],
    );
    final categoryTranslation = await database.database.query(
      'category_translations',
      where: 'category_id = ? AND locale = ?',
      whereArgs: ['category.food', 'zh-Hans'],
    );

    expect(recurring.single['status'], 'archived');
    expect(subscription.single['status'], 'active');
    expect(userTag.single['name'], 'Keep me');
    expect(translation.single['label'], 'Viajes');
    expect(categoryTranslation.single['label'], '餐饮');
  });
}
