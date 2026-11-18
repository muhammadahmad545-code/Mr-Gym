import 'package:flutter/foundation.dart';

import 'crypto.dart';
import 'prefs.dart';

/// Optional PIN lock. Off until the owner turns it on in Settings.
class AppLock extends ChangeNotifier {
  AppLock(this._prefs) : _locked = _prefs.pinEnabled;

  final AppPrefs _prefs;
  bool _locked;
  DateTime? _backgroundSince;

  static const minLength = 4;
  static const maxLength = 8;

  bool get enabled => _prefs.pinEnabled;
  bool get locked => _locked && enabled;

  static String? validate(String pin) {
    if (!RegExp(r'^\d+$').hasMatch(pin) || pin.length < minLength || pin.length > maxLength) {
      return 'Use $minLength to $maxLength digits.';
    }
    return null;
  }

  Future<void> enable(String pin) async {
    final error = validate(pin);
    if (error != null) throw ArgumentError(error);
    final (hash, salt) = await GymCrypto.hashNewPin(pin);
    await _prefs.setPin(hash, salt);
    _locked = false;
    notifyListeners();
  }

  Future<void> disable() async {
    await _prefs.clearPin();
    _locked = false;
    notifyListeners();
  }

  Duration? get lockoutRemaining {
    final until = _prefs.pinLockedUntil;
    if (until == null) return null;
    final left = until.difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  /// Returns null when the PIN is right, otherwise a message for the user.
  Future<String?> check(String pin, {bool unlockOnSuccess = true}) async {
    final wait = lockoutRemaining;
    if (wait != null) return 'Too many attempts. Try again in ${_fmt(wait)}.';
    final ok = await GymCrypto.verifyPin(pin, _prefs.pinHash ?? '', _prefs.pinSalt ?? '');
    if (ok) {
      await _prefs.setPinFailures(0, null);
      if (unlockOnSuccess) {
        _locked = false;
        notifyListeners();
      }
      return null;
    }
    final failures = _prefs.pinFailures + 1;
    final lockFor = failures >= 10
        ? const Duration(minutes: 15)
        : failures >= 8
            ? const Duration(minutes: 5)
            : failures >= 5
                ? const Duration(seconds: 30)
                : null;
    await _prefs.setPinFailures(failures, lockFor == null ? null : DateTime.now().add(lockFor));
    if (lockFor != null) return 'Too many attempts. Try again in ${_fmt(lockFor)}.';
    return 'Wrong PIN. Try again.';
  }

  void lockNow() {
    if (!enabled) return;
    _locked = true;
    notifyListeners();
  }

  void onBackground() => _backgroundSince ??= DateTime.now();

  void onForeground() {
    final since = _backgroundSince;
    _backgroundSince = null;
    if (since != null && enabled && DateTime.now().difference(since).inMinutes >= _prefs.autoLockMinutes) {
      lockNow();
    }
  }

  static String _fmt(Duration d) => d.inMinutes >= 1 ? '${d.inMinutes + (d.inSeconds % 60 > 0 ? 1 : 0)} min' : '${d.inSeconds.clamp(1, 59)} s';
}
