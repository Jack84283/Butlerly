import 'dart:convert';
import 'dart:io';

import '../test/core/evidence/support/receipt_layout_fixture.dart';

/// Generates a readable, position-preserving .txt beside an OCR fixture JSON.
/// Only the JSON is used by production extraction regression tests.
void main(List<String> args) {
  if (args.length != 1 || !args.single.toLowerCase().endsWith('.json')) {
    stderr.writeln(
      'Usage: dart run tool/generate_receipt_layout.dart '
      'test/core/evidence/fixtures/<receipt>.json',
    );
    exitCode = 64;
    return;
  }

  final source = File(args.single);
  if (!source.existsSync()) {
    stderr.writeln('Fixture not found: ${source.path}');
    exitCode = 66;
    return;
  }

  final destination = File(
    '${source.path.substring(0, source.path.length - 5)}.txt',
  );

  try {
    final fixture = ReceiptLayoutFixture.fromJson(
      jsonDecode(source.readAsStringSync()) as Map<String, dynamic>,
    );
    final output = '${fixture.layout}\n';
    if (destination.existsSync() && destination.readAsStringSync() == output) {
      stdout.writeln('Already up to date: ${destination.path}');
      return;
    }
    destination.writeAsStringSync(output);
    stdout.writeln('Created receipt layout: ${destination.path}');
    stdout.writeln(
      'Reminder: review and redact receipt text before committing files.',
    );
  } on FormatException catch (error) {
    stderr.writeln('Invalid fixture JSON: $error');
    exitCode = 65;
  } on TypeError catch (error) {
    stderr.writeln('Invalid fixture schema: $error');
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln('Cannot read or write receipt layout: $error');
    exitCode = 74;
  }
}
