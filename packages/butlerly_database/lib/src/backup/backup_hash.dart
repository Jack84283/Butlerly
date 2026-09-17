import 'dart:io';
import 'dart:typed_data';

String sha256Bytes(List<int> bytes) {
  final digest = _Sha256Accumulator()..add(bytes);
  return digest.close();
}

Future<String> sha256FileRange(
  File file, {
  int start = 0,
  int? endExclusive,
}) async {
  final digest = _Sha256Accumulator();
  await for (final chunk in file.openRead(start, endExclusive)) {
    digest.add(chunk);
  }
  return digest.close();
}

Uint8List int64Bytes(int value) {
  final data = ByteData(8)..setInt64(0, value, Endian.big);
  return data.buffer.asUint8List();
}

int int64FromBytes(List<int> bytes) {
  if (bytes.length != 8) {
    throw const FormatException('Invalid 64-bit backup field.');
  }
  return ByteData.sublistView(
    Uint8List.fromList(bytes),
  ).getInt64(0, Endian.big);
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

final class _Sha256Accumulator {
  static const _initial = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];

  static const _round = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  final _state = List<int>.of(_initial);
  final _buffer = <int>[];
  var _byteLength = 0;
  var _closed = false;

  void add(List<int> bytes) {
    if (_closed) throw StateError('SHA-256 accumulator is already closed.');
    _byteLength += bytes.length;
    var offset = 0;

    if (_buffer.isNotEmpty) {
      final needed = 64 - _buffer.length;
      final take = bytes.length < needed ? bytes.length : needed;
      _buffer.addAll(bytes.sublist(0, take));
      offset = take;
      if (_buffer.length == 64) {
        _compress(_buffer);
        _buffer.clear();
      }
    }

    while (offset + 64 <= bytes.length) {
      _compress(bytes.sublist(offset, offset + 64));
      offset += 64;
    }
    if (offset < bytes.length) {
      _buffer.addAll(bytes.sublist(offset));
    }
  }

  String close() {
    if (_closed) throw StateError('SHA-256 accumulator is already closed.');
    _closed = true;
    final bitLength = _byteLength * 8;
    _buffer.add(0x80);
    while ((_buffer.length % 64) != 56) {
      _buffer.add(0);
    }
    final lengthBytes = ByteData(8)..setUint64(0, bitLength, Endian.big);
    _buffer.addAll(lengthBytes.buffer.asUint8List());
    for (var offset = 0; offset < _buffer.length; offset += 64) {
      _compress(_buffer.sublist(offset, offset + 64));
    }
    return _state
        .map((value) => value.toRadixString(16).padLeft(8, '0'))
        .join();
  }

  void _compress(List<int> block) {
    final words = List<int>.filled(64, 0);
    final data = ByteData.sublistView(Uint8List.fromList(block));
    for (var index = 0; index < 16; index++) {
      words[index] = data.getUint32(index * 4, Endian.big);
    }
    for (var index = 16; index < 64; index++) {
      final s0 =
          _rotateRight(words[index - 15], 7) ^
          _rotateRight(words[index - 15], 18) ^
          (words[index - 15] >> 3);
      final s1 =
          _rotateRight(words[index - 2], 17) ^
          _rotateRight(words[index - 2], 19) ^
          (words[index - 2] >> 10);
      words[index] = _u32(words[index - 16] + s0 + words[index - 7] + s1);
    }

    var a = _state[0];
    var b = _state[1];
    var c = _state[2];
    var d = _state[3];
    var e = _state[4];
    var f = _state[5];
    var g = _state[6];
    var h = _state[7];

    for (var index = 0; index < 64; index++) {
      final bigS1 =
          _rotateRight(e, 6) ^ _rotateRight(e, 11) ^ _rotateRight(e, 25);
      final choose = (e & f) ^ ((~e) & g);
      final temp1 = _u32(h + bigS1 + choose + _round[index] + words[index]);
      final bigS0 =
          _rotateRight(a, 2) ^ _rotateRight(a, 13) ^ _rotateRight(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = _u32(bigS0 + majority);

      h = g;
      g = f;
      f = e;
      e = _u32(d + temp1);
      d = c;
      c = b;
      b = a;
      a = _u32(temp1 + temp2);
    }

    _state[0] = _u32(_state[0] + a);
    _state[1] = _u32(_state[1] + b);
    _state[2] = _u32(_state[2] + c);
    _state[3] = _u32(_state[3] + d);
    _state[4] = _u32(_state[4] + e);
    _state[5] = _u32(_state[5] + f);
    _state[6] = _u32(_state[6] + g);
    _state[7] = _u32(_state[7] + h);
  }

  static int _rotateRight(int value, int count) =>
      _u32((value >> count) | (value << (32 - count)));

  static int _u32(int value) => value & 0xffffffff;
}
