import 'dart:io';

import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

DatabaseFactory createDatabaseFactory() {
  if (Platform.isAndroid || Platform.isIOS) {
    return databaseFactory;
  }

  sqfliteFfiInit();
  return databaseFactoryFfi;
}
