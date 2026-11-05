import 'dart:io';

import 'package:butlerly/core/data/atomic_evidence_publication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('atomic no-replace link exposes a fully verified file', () async {
    if (!Platform.isLinux) return; // Host CI tests the POSIX hard-link path.
    final root = await Directory.systemTemp.createTemp('atomic-evidence-');
    addTearDown(() => root.delete(recursive: true));
    final staging = File(path.join(root.path, 'verified-staging'));
    final target = File(path.join(root.path, 'receipt.pdf'));
    await staging.writeAsBytes([1, 2, 3, 4]);
    await AtomicEvidencePublication.publishNoReplace(staging, target);
    expect(await target.readAsBytes(), [1, 2, 3, 4]);
    await staging.delete();
    expect(await target.readAsBytes(), [1, 2, 3, 4]);
  });

  test('atomic link never replaces a competing attachment', () async {
    if (!Platform.isLinux) return;
    final root = await Directory.systemTemp.createTemp('atomic-evidence-');
    addTearDown(() => root.delete(recursive: true));
    final staging = File(path.join(root.path, 'verified-staging'));
    final target = File(path.join(root.path, 'receipt.pdf'));
    await staging.writeAsBytes([1, 2, 3, 4]);
    await target.writeAsBytes([9, 8, 7]);
    await expectLater(
      AtomicEvidencePublication.publishNoReplace(staging, target),
      throwsA(isA<FileSystemException>()),
    );
    expect(await target.readAsBytes(), [9, 8, 7]);
    expect(await staging.readAsBytes(), [1, 2, 3, 4]);
  });
}
