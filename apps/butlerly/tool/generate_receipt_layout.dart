import 'dart:convert';
import 'dart:io';

import '../test/core/evidence/support/receipt_layout_fixture.dart';
import '../test/core/evidence/support/receipt_text_json.dart';

/// Writes aligned TXT first from original OCR evidence and then derives a
/// separate .extracted.json from the saved TXT. Developer/test tooling only.
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

  final stem = source.path.substring(0, source.path.length - 5);
  final destination = File('$stem.txt');
  final structured = File('$stem.extracted.json');

  try {
    final fixture = ReceiptLayoutFixture.fromJson(
      jsonDecode(source.readAsStringSync()) as Map<String, dynamic>,
    );
    final output = '${fixture.layout}\n';
    // Read exactly what was written. The extracted JSON is never based on
    // the expected fields or original OCR geometry.
    if (!destination.existsSync() || destination.readAsStringSync() != output) {
      destination.writeAsStringSync(output);
    }
    final savedText = destination.readAsStringSync();
    final json = '${ReceiptTextJson.encode(savedText)}\n';
    if (!structured.existsSync() || structured.readAsStringSync() != json) {
      structured.writeAsStringSync(json);
    }
    stdout.writeln('Aligned text: ${destination.path}');
    stdout.writeln('JSON derived from saved text: ${structured.path}');
    stdout.writeln(
      'Reminder: redact personal and payment information before sharing.',
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
