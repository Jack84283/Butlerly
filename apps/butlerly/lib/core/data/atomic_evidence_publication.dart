import 'dart:io';

import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:flutter/services.dart';

/// Publish fully verified private bytes to a new evidence name atomically.
///
/// Both paths must be on the same filesystem for hard-link publication.
/// The OS guarantees that a hard-link creation either publishes the complete
/// file inode under the new name or fails without changing that pathname.
/// Unlike File.rename, hard-link creation never replaces an existing file.
/// Unsupported hosts/filesystems fail closed, rather than exposing a partial
/// receipt under the final name.
final class AtomicEvidencePublication {
  AtomicEvidencePublication._();

  static const _channel = MethodChannel('butlerly/storage_capacity');

  static Future<void> publishNoReplace(File source, File destination) async {
    await rejectSymlinkedPath(source.path);
    await rejectSymlinkedPath(destination.path);
    if (Platform.isLinux) {
      // ln without -f is an atomic link(2), not a file copy. Delimit options
      // so untrusted filename components cannot become command-line flags.
      final output = await Process.run('ln', [
        '--',
        source.path,
        destination.path,
      ]);
      if (output.exitCode != 0) {
        throw FileSystemException(
          'Atomic evidence publication failed (destination exists, or '
          'the filesystem does not support hard links).',
          destination.path,
        );
      }
      return;
    }

    try {
      await _channel.invokeMethod<void>('publishNoReplace', {
        'source': source.path,
        'destination': destination.path,
      });
    } on MissingPluginException {
      throw FileSystemException(
        'Atomic no-replace evidence publication is unsupported on this host.',
        destination.path,
      );
    } on PlatformException {
      throw FileSystemException(
        'Atomic evidence publication failed (destination exists, or '
        'the filesystem does not support hard links).',
        destination.path,
      );
    }
  }
}
