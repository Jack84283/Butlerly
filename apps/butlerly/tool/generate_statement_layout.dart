import 'dart:convert';
import 'dart:io';

import '../test/core/evidence/support/statement_layout_fixture.dart';

/// Outputs an aligned UTF-8 diagnostic TXT from a redacted statement OCR JSON.
/// This does not modify production statement recognition or extraction.
void main(List<String> args) {
  if (args.length != 1 || !args.single.toLowerCase().endsWith('.json')) {
    stderr.writeln(
      'Usage: dart run tool/generate_statement_layout.dart '
      'test/core/evidence/fixtures/<statement>.json',
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
    final fixture = StatementLayoutFixture.fromJson(
      jsonDecode(source.readAsStringSync()) as Map<String, dynamic>,
    );
    final output = '${fixture.layout}\n';
    if (destination.existsSync() && destination.readAsStringSync() == output) {
      stdout.writeln('Already up to date: ${destination.path}');
      return;
    }
    destination.writeAsStringSync(output);
    stdout.writeln('Created statement layout: ${destination.path}');
    stdout.writeln(
      'Reminder: redact account and financial information before sharing.',
    );
  } on FormatException catch (error) {
    stderr.writeln('Invalid statement fixture JSON: $error');
    exitCode = 65;
  } on TypeError catch (error) {
    stderr.writeln('Invalid statement fixture schema: $error');
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln('Cannot read or write statement layout: $error');
    exitCode = 74;
  }
}
