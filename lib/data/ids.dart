import 'dart:math';

final _random = Random.secure();

/// Random 128-bit id as 32 hex characters.
String newId() {
  final b = StringBuffer();
  for (var i = 0; i < 16; i++) {
    b.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}
