import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'butlerly_csv_template.dart';

/// Exports exact UTF-8 templates to a user-selected location without network.
Future<bool> downloadButlerlyCsvTemplate(ButlerlyCsvKind kind) async {
  final filename = ButlerlyCsvTemplate.filename(kind);
  final bytes = Uint8List.fromList(
    utf8.encode(ButlerlyCsvTemplate.content(kind)),
  );
  final file = XFile.fromData(bytes, mimeType: 'text/csv', name: filename);
  final desktop = !kIsWeb &&
      {TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux}
          .contains(defaultTargetPlatform);
  if (desktop) {
    final location = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (location == null) return false;
    await file.saveTo(location.path);
    return true;
  }
  // Mobile provides Save to Files via its share sheet; the share_plus web
  // fallback downloads the CSV where the Web Share API is unavailable.
  final result = await SharePlus.instance.share(
    ShareParams(
      files: [file],
      fileNameOverrides: [filename],
      title: filename,
    ),
  );
  return result.status != ShareResultStatus.dismissed;
}
