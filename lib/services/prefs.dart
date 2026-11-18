import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device settings (not part of backups): theme, intro, app lock and reminder preferences.
class AppPrefs extends ChangeNotifier {
  AppPrefs(this._p);

  final SharedPreferences _p;

  static Future<AppPrefs> load() async => AppPrefs(await SharedPreferences.getInstance());

  ThemeMode get themeMode => switch (_p.getString('theme')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
  Future<void> setThemeMode(ThemeMode m) async {
    await _p.setString('theme', m.name);
    notifyListeners();
  }

  bool get onboarded => _p.getBool('onboarded') ?? false;
  Future<void> setOnboarded() async {
    await _p.setBool('onboarded', true);
    notifyListeners();
  }

  // Reminders
  bool get feeReminders => _p.getBool('reminders.fees') ?? true;
  bool get backupReminders => _p.getBool('reminders.backup') ?? true;
  TimeOfDay get reminderTime =>
      TimeOfDay(hour: _p.getInt('reminders.hour') ?? 9, minute: _p.getInt('reminders.minute') ?? 0);
  int get backupEveryDays => _p.getInt('reminders.backupDays') ?? 7;

  Future<void> setFeeReminders(bool v) async {
    await _p.setBool('reminders.fees', v);
    notifyListeners();
  }

  Future<void> setBackupReminders(bool v) async {
    await _p.setBool('reminders.backup', v);
    notifyListeners();
  }

  Future<void> setReminderTime(TimeOfDay t) async {
    await _p.setInt('reminders.hour', t.hour);
    await _p.setInt('reminders.minute', t.minute);
    notifyListeners();
  }

  Future<void> setBackupEveryDays(int d) async {
    await _p.setInt('reminders.backupDays', d);
    notifyListeners();
  }

  DateTime? get lastBackupAt {
    final ms = _p.getInt('backup.last');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastBackupAt(DateTime t) async {
    await _p.setInt('backup.last', t.millisecondsSinceEpoch);
    notifyListeners();
  }

  // App lock (hash and salt only; the PIN itself is never stored).
  String? get pinHash => _p.getString('pin.hash');
  String? get pinSalt => _p.getString('pin.salt');
  bool get pinEnabled => (pinHash ?? '').isNotEmpty && (pinSalt ?? '').isNotEmpty;
  int get pinFailures => _p.getInt('pin.failures') ?? 0;
  DateTime? get pinLockedUntil {
    final ms = _p.getInt('pin.lockedUntil');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setPin(String hash, String salt) async {
    await _p.setString('pin.hash', hash);
    await _p.setString('pin.salt', salt);
    await _p.remove('pin.failures');
    await _p.remove('pin.lockedUntil');
    notifyListeners();
  }

  Future<void> clearPin() async {
    await _p.remove('pin.hash');
    await _p.remove('pin.salt');
    await _p.remove('pin.failures');
    await _p.remove('pin.lockedUntil');
    notifyListeners();
  }

  Future<void> setPinFailures(int n, DateTime? lockedUntil) async {
    await _p.setInt('pin.failures', n);
    if (lockedUntil == null) {
      await _p.remove('pin.lockedUntil');
    } else {
      await _p.setInt('pin.lockedUntil', lockedUntil.millisecondsSinceEpoch);
    }
  }

  /// Lock again after this long in the background.
  int get autoLockMinutes => _p.getInt('pin.autoLockMinutes') ?? 1;
  Future<void> setAutoLockMinutes(int m) async {
    await _p.setInt('pin.autoLockMinutes', m);
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _p.clear();
    notifyListeners();
  }
}
