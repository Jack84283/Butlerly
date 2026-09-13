import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

final class BackupPasswordRequiredException implements Exception {
  const BackupPasswordRequiredException();
}

final class BackupPasswordTooShortException implements Exception {
  const BackupPasswordTooShortException();
}

final class BackupPasswordOrIntegrityException implements Exception {
  const BackupPasswordOrIntegrityException();
}

/// Password-protected wrapper for user-managed portable Butlerly backups.
///
/// The inner Butlerly backup remains unchanged. This wrapper protects the whole
/// inner package with Argon2id-derived AES-256-GCM authenticated encryption.
/// The small outer header contains only algorithm parameters required before
/// decryption and is authenticated as AES-GCM associated data.
final class BackupEncryption {
  const BackupEncryption();

  static final magic = utf8.encode('BUTLERLYENC1');
  static const version = 1;
  static const minimumPasswordLength = 12;
  static const _maximumHeaderLength = 64 * 1024;
  static const _macLength = 16;
  static const _argonMemoryKiB = 19 * 1024;
  static const _argonIterations = 2;
  static const _argonParallelism = 1;
  static const _saltLength = 16;

  static final _cipher = AesGcm.with256bits();
  static final _kdf = Argon2id(
    memory: _argonMemoryKiB,
    parallelism: _argonParallelism,
    iterations: _argonIterations,
    hashLength: 32,
  );

  Future<bool> isEncrypted(File file) async {
    if (!await file.exists() || await file.length() < magic.length) return false;
    final input = await file.open(mode: FileMode.read);
    try {
      final value = await input.read(magic.length);
      return _listEquals(value, magic);
    } finally {
      await input.close();
    }
  }

  Future<File> encrypt(
    File source,
    File destination, {
    required String password,
  }) async {
    if (password.length < minimumPasswordLength) {
      throw const BackupPasswordTooShortException();
    }

    final random = Random.secure();
    final salt = List<int>.generate(
      _saltLength,
      (_) => random.nextInt(256),
      growable: false,
    );
    final nonce = _cipher.newNonce();
    final header = <String, Object?>{
      'format': 'butlerly-encrypted-backup',
      'version': version,
      'cipher': 'AES-256-GCM',
      'kdf': 'Argon2id',
      'kdfMemoryKiB': _argonMemoryKiB,
      'kdfIterations': _argonIterations,
      'kdfParallelism': _argonParallelism,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'innerFormat': 'butlerly-backup-v2',
    };
    final headerBytes = utf8.encode(jsonEncode(header));
    final secretKey = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );

    await destination.parent.create(recursive: true);
    final temporary = File(
      '${destination.path}.encrypting-${DateTime.now().microsecondsSinceEpoch}',
    );
    final output = temporary.openWrite();
    try {
      output.add(magic);
      output.add(_encodeInt64(headerBytes.length));
      output.add(headerBytes);

      late Mac mac;
      final encrypted = _cipher.encryptStream(
        source.openRead(),
        secretKey: secretKey,
        nonce: nonce,
        aad: headerBytes,
        onMac: (value) => mac = value,
      );
      await output.addStream(encrypted);
      output.add(mac.bytes);
      await output.flush();
    } finally {
      await output.close();
    }

    try {
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    return destination;
  }

  Future<File> decrypt(
    File source,
    File destination, {
    required String password,
  }) async {
    if (password.isEmpty) throw const BackupPasswordRequiredException();

    final input = await source.open(mode: FileMode.read);
    late List<int> headerBytes;
    late List<int> nonce;
    late List<int> salt;
    late int cipherStart;
    late int cipherEnd;
    late List<int> macBytes;
    try {
      final encryptedMagic = await input.read(magic.length);
      if (!_listEquals(encryptedMagic, magic)) {
        throw const FormatException('Not an encrypted Butlerly backup.');
      }
      final lengthBytes = await input.read(8);
      if (lengthBytes.length != 8) {
        throw const FormatException('Incomplete encrypted backup header.');
      }
      final headerLength = _decodeInt64(lengthBytes);
      if (headerLength <= 0 || headerLength > _maximumHeaderLength) {
        throw const FormatException('Invalid encrypted backup header length.');
      }
      headerBytes = await input.read(headerLength);
      if (headerBytes.length != headerLength) {
        throw const FormatException('Incomplete encrypted backup header.');
      }
      final decoded = jsonDecode(utf8.decode(headerBytes));
      if (decoded is! Map) {
        throw const FormatException('Invalid encrypted backup header.');
      }
      final header = decoded.cast<String, Object?>();
      if (header['format'] != 'butlerly-encrypted-backup' ||
          header['version'] != version ||
          header['cipher'] != 'AES-256-GCM' ||
          header['kdf'] != 'Argon2id' ||
          header['kdfMemoryKiB'] != _argonMemoryKiB ||
          header['kdfIterations'] != _argonIterations ||
          header['kdfParallelism'] != _argonParallelism) {
        throw const FormatException('Unsupported encrypted backup format.');
      }
      salt = base64Decode(header['salt']! as String);
      nonce = base64Decode(header['nonce']! as String);
      if (salt.length != _saltLength || nonce.length != _cipher.nonceLength) {
        throw const FormatException('Invalid encrypted backup parameters.');
      }

      cipherStart = magic.length + 8 + headerLength;
      final totalLength = await source.length();
      cipherEnd = totalLength - _macLength;
      if (cipherEnd < cipherStart) {
        throw const FormatException('Incomplete encrypted backup payload.');
      }
      await input.setPosition(cipherEnd);
      macBytes = await input.read(_macLength);
      if (macBytes.length != _macLength) {
        throw const FormatException(
          'Incomplete encrypted backup authentication.',
        );
      }
    } finally {
      await input.close();
    }

    final secretKey = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    await destination.parent.create(recursive: true);
    final output = destination.openWrite();
    Object? failure;
    StackTrace? failureStack;
    try {
      final clearText = _cipher.decryptStream(
        source.openRead(cipherStart, cipherEnd),
        secretKey: secretKey,
        nonce: nonce,
        mac: Mac(macBytes),
        aad: headerBytes,
      );
      await output.addStream(clearText);
      await output.flush();
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    }
    try {
      await output.close();
    } catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    }

    if (failure != null) {
      if (await destination.exists()) await destination.delete();
      if (failure is SecretBoxAuthenticationError) {
        throw const BackupPasswordOrIntegrityException();
      }
      Error.throwWithStackTrace(failure, failureStack ?? StackTrace.current);
    }
    return destination;
  }

  static Uint8List _encodeInt64(int value) {
    final bytes = ByteData(8)..setUint64(0, value, Endian.big);
    return bytes.buffer.asUint8List();
  }

  static int _decodeInt64(List<int> bytes) {
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    return data.getUint64(0, Endian.big);
  }

  static bool _listEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
