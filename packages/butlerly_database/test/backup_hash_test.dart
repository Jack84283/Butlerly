import 'dart:convert';
import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:test/test.dart';

void main() {
  test('sha256Bytes matches the standard abc vector', () {
    expect(
      sha256Bytes(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('sha256FileRange hashes only the requested byte range', () async {
    final directory = await Directory.systemTemp.createTemp('butlerly-hash-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/payload.bin');
    await file.writeAsBytes([0, ...utf8.encode('abc'), 0]);

    expect(
      await sha256FileRange(file, start: 1, endExclusive: 4),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
}
