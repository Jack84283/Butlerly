import 'dart:convert';
import 'dart:io';

import '../test/core/evidence/support/statement_layout_fixture.dart';
import '../test/core/evidence/support/statement_text_json.dart';

/// Writes aligned TXT first from raw OCR evidence, then transcribes TXT rows
/// into a separate .extracted.json. Production extraction remains unchanged.
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
  final stem = source.path.substring(0, source.path.length - 5);
  final destination = File('$stem.txt');
  final structured = File('$stem.extracted.json');
  try {
    final fixture = StatementLayoutFixture.fromJson(
      jsonDecode(source.readAsStringSync()) as Map<String, dynamic>,
    );
    final output = '${fixture.layout}\n';
    // Materialize TXT *before* constructing the semantic JSON. The JSON is
    // derived from the exact bytes saved to the TXT file, not from the
    // original OCR geometry or any preexisting expected transaction values.
    if (!destination.existsSync() || destination.readAsStringSync() != output) {
      destination.writeAsStringSync(output);
    }
    final savedText = destination.readAsStringSync();
    final derived = '${StatementTextJson.encode(savedText)}\n';
    if (!structured.existsSync() || structured.readAsStringSync() != derived) {
      structured.writeAsStringSync(derived);
    }
    stdout.writeln('Aligned text: ${destination.path}');
    stdout.writeln('JSON derived from saved text: ${structured.path}');
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
