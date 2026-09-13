/// Small database-package helper for extracting SQLite aggregate results
/// without depending on package-specific convenience APIs in application code.
abstract final class Sqflite {
  static int? firstIntValue(List<Map<String, Object?>> rows) {
    if (rows.isEmpty || rows.first.isEmpty) return null;
    final value = rows.first.values.first;
    return value is int ? value : null;
  }
}
