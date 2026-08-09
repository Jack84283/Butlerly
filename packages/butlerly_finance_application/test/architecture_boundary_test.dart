import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('application source has no Flutter or infrastructure imports', () {
    final forbidden = RegExp(
      r'''import ['"](?:package:flutter|package:sqflite|package:butlerly_database|dart:io|dart:ffi|dart:html)''',
    );
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      expect(
        file.readAsStringSync(),
        isNot(matches(forbidden)),
        reason: '${file.path} must remain infrastructure-independent.',
      );
    }
  });
}
