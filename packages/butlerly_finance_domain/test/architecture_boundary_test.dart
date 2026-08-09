import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('domain source has no Flutter, SQLite, network, or platform imports', () {
    final forbidden = RegExp(
      r'''import ['"](?:package:flutter|package:sqflite|dart:io|dart:ffi|dart:html)''',
    );
    final files = Directory('lib').listSync(recursive: true).whereType<File>();

    for (final file in files) {
      expect(
        file.readAsStringSync(),
        isNot(matches(forbidden)),
        reason: '${file.path} must remain a pure Dart domain source.',
      );
    }
  });
}
