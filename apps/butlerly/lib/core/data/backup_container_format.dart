import 'dart:convert';

/// Persisted backup protocol constants. Change these only with an explicit
/// compatibility/migration decision, independently of UI or device defaults.
abstract final class BackupContainerFormat {
  static const name = 'butlerly-backup';
  static const version = 2;
  static const schemaVersion = 8;
  static List<int> get magic => utf8.encode('BUTLERLYBACKUP2');
  static const appVersion = String.fromEnvironment(
    'BUTLERLY_APP_VERSION',
    defaultValue: '1.0.0',
  );
  static const appBuild = String.fromEnvironment(
    'BUTLERLY_APP_BUILD',
    defaultValue: '1',
  );
}
