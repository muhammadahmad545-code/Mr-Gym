import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

/// PIN hashing and backup encryption (PBKDF2-SHA256 + AES-256-GCM). Never log outputs.
abstract final class GymCrypto {
  static const backupFormatVersion = '1';
  static const pinIterations = 60000;
  static const backupIterations = 150000;

  static final _random = Random.secure();

  static Uint8List randomBytes(int n) => Uint8List.fromList([for (var i = 0; i < n; i++) _random.nextInt(256)]);

  static Uint8List pbkdf2(String password, Uint8List salt, int iterations, [int length = 32]) {
    final d = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(salt, iterations, length));
    return d.process(Uint8List.fromList(utf8.encode(password)));
  }

  /// Returns (hash, salt) as base64. Runs off the UI thread.
  static Future<(String, String)> hashNewPin(String pin) async {
    final salt = base64Encode(randomBytes(16));
    final hash = await compute(_pinHashTask, [pin, salt]);
    return (hash, salt);
  }

  static Future<bool> verifyPin(String pin, String hashB64, String saltB64) async {
    if (hashB64.isEmpty || saltB64.isEmpty) return false;
    final actual = await compute(_pinHashTask, [pin, saltB64]);
    return constantTimeEquals(actual, hashB64);
  }

  static Future<Map<String, Object>> encryptAsync(Uint8List plain, String password) =>
      compute(_encryptTask, (plain, password));

  static Future<Uint8List> decryptAsync(Map<String, dynamic> package, String password) =>
      compute(_decryptTask, (package, password));

  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  /// Encrypts [plain] into a JSON-serialisable package. Same format as Mr. Gym 1.x backups.
  static Map<String, Object> encrypt(Uint8List plain, String password) {
    final salt = randomBytes(16);
    final iv = randomBytes(12);
    final key = pbkdf2(password, salt, backupIterations);
    final cipher = GCMBlockCipher(AESEngine())..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final out = cipher.process(plain);
    key.fillRange(0, key.length, 0);
    return {
      'formatVersion': backupFormatVersion,
      'kdf': 'pbkdf2-sha256',
      'iterations': backupIterations,
      'salt': base64Encode(salt),
      'iv': base64Encode(iv),
      'ciphertext': base64Encode(out),
      'sha256': sha256Hex(plain),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Throws [ArgumentError] for a wrong password or damaged data.
  static Uint8List decrypt(Map<String, dynamic> package, String password) {
    final iterations = (package['iterations'] as num?)?.toInt() ?? backupIterations;
    final salt = base64Decode(package['salt'] as String);
    final iv = base64Decode(package['iv'] as String);
    final data = base64Decode(package['ciphertext'] as String);
    final key = pbkdf2(password, Uint8List.fromList(salt), iterations);
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), 128, Uint8List.fromList(iv), Uint8List(0)));
      return cipher.process(Uint8List.fromList(data));
    } catch (_) {
      throw ArgumentError('wrong password or damaged backup');
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }
}

String _pinHashTask(List<String> a) => base64Encode(GymCrypto.pbkdf2(a[0], base64Decode(a[1]), GymCrypto.pinIterations));

Map<String, Object> _encryptTask((Uint8List, String) a) => GymCrypto.encrypt(a.$1, a.$2);

Uint8List _decryptTask((Map<String, dynamic>, String) a) => GymCrypto.decrypt(a.$1, a.$2);
