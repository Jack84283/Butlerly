import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

String sha256Bytes(List<int> bytes) => sha256.convert(bytes).toString();

Future<String> sha256FileRange(
  File file, {
  int start = 0,
  int? endExclusive,
}) async {
  final digest = await sha256.bind(file.openRead(start, endExclusive)).first;
  return digest.toString();
}

Future<void> copyFileRange(
  File source,
  IOSink destination, {
  int start = 0,
  int? endExclusive,
}) async {
  await destination.addStream(source.openRead(start, endExclusive));
}

Uint8List int64Bytes(int value) {
  final data = ByteData(8)..setInt64(0, value, Endian.big);
  return data.buffer.asUint8List();
}

int int64FromBytes(List<int> bytes) {
  if (bytes.length != 8) {
    throw const FormatException('Invalid 64-bit backup field.');
  }
  return ByteData.sublistView(Uint8List.fromList(bytes)).getInt64(0, Endian.big);
}
