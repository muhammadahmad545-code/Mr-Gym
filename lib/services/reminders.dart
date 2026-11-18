import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/gym_repository.dart';
import '../domain/dates.dart';
import '../domain/member_view.dart';
import 'prefs.dart';

@immutable
class PlannedReminder {
  const PlannedReminder({required this.id, required this.when, required this.title, required this.body});
  final int id;
  final DateTime when;
  final String title;
  final String body;

  @override
  String toString() => 'PlannedReminder($id, $when, $title, $body)';
}

/// How many days ahead reminders are scheduled. Opening the app (or any change) re-plans them.
const reminderHorizonDays = 30;
const _feeIdBase = 1000;
const _backupIdBase = 2000;

/// Works out the daily reminder notifications for the next [days] days, assuming nothing is paid
/// in the meantime (any payment re-plans them).
List<PlannedReminder> planReminders({
  required List<MemberView> members,
  required DateTime now,
  required TimeOfDay time,
  required bool fees,
  required bool backups,
  required DateTime? lastBackup,
  required int backupEveryDays,
  int days = reminderHorizonDays,
}) {
  final out = <PlannedReminder>[];
  final start = dateOnly(now);
  final billable = members.where((m) => m.isBillable).toList();
  final hasMembers = members.any((m) => !m.isInactive);
  final backupDue = lastBackup == null ? start : addDays(dateOnly(lastBackup), backupEveryDays);

  for (var i = 0; i < days; i++) {
    final day = addDays(start, i);
    final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    if (!at.isAfter(now)) continue;

    if (fees) {
      final dueToday = billable.where((m) => sameDay(m.due, day)).toList();
      final overdue = billable.where((m) => m.due.isBefore(day)).toList();
      if (dueToday.isNotEmpty || overdue.isNotEmpty) {
        final title = dueToday.isNotEmpty
            ? '${dueToday.length} ${dueToday.length == 1 ? 'fee' : 'fees'} due today'
            : '${overdue.length} overdue ${overdue.length == 1 ? 'fee' : 'fees'}';
        final parts = <String>[
          if (dueToday.isNotEmpty) 'Due today: ${_names(dueToday)}',
          if (overdue.isNotEmpty) 'Overdue: ${overdue.length == 1 ? overdue.first.name : '${overdue.length} members'}',
        ];
        out.add(PlannedReminder(id: _feeIdBase + i, when: at, title: title, body: '${parts.join('. ')}.'));
      }
    }

    if (backups && hasMembers && !day.isBefore(backupDue) && daysBetween(backupDue, day) % 3 == 0) {
      final body = lastBackup == null
          ? "You haven't backed up your gym data yet. Open Settings > Backup to save a copy."
          : 'Your last backup was ${daysBetween(dateOnly(lastBackup), day)} days ago. Open Settings > Backup to save a copy.';
      out.add(PlannedReminder(id: _backupIdBase + i, when: at, title: 'Time to back up', body: body));
    }
  }
  return out;
}

String _names(List<MemberView> list) {
  final names = list.take(3).map((m) => m.name).join(', ');
  return list.length > 3 ? '$names +${list.length - 3} more' : names;
}

/// Schedules the planned reminders with the OS (AlarmManager), so they fire even when the app is
/// closed. flutter_local_notifications restores them after a reboot or app update.
class ReminderService {
  ReminderService({required this.repo, required this.prefs, this.platformEnabled = true});

  final GymRepository repo;
  final AppPrefs prefs;

  /// False in tests, where there is no notification plugin.
  final bool platformEnabled;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _running = false;
  bool _again = false;

  Future<bool> _init() async {
    if (_ready) return true;
    if (!platformEnabled || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    tzdata.initializeTimeZones();
    await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('ic_stat_gym')));
    _ready = true;
    return true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Asks for the notification permission (Android 13+). Returns whether notifications are allowed.
  Future<bool> requestPermission() async {
    try {
      if (!await _init()) return false;
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('reminders: permission request failed: $e');
      return false;
    }
  }

  Future<bool> notificationsAllowed() async {
    try {
      if (!await _init()) return false;
      return await _android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Re-plans every reminder from current data. Safe to call often; calls are coalesced.
  Future<void> reschedule() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _reschedule();
      } while (_again);
    } catch (e) {
      debugPrint('reminders: reschedule failed: $e');
    } finally {
      _running = false;
    }
  }

  Future<void> _reschedule() async {
    if (!await _init()) return;
    final now = DateTime.now();
    final members = [for (final m in await repo.members()) MemberView(m, now)];
    final planned = planReminders(
      members: members,
      now: now,
      time: prefs.reminderTime,
      fees: prefs.feeReminders,
      backups: prefs.backupReminders,
      lastBackup: prefs.lastBackupAt,
      backupEveryDays: prefs.backupEveryDays,
    );
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (p.id >= _feeIdBase && p.id < _backupIdBase + 1000) await _plugin.cancel(p.id);
    }
    for (final r in planned) {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'mrgym_reminders',
          'Daily reminders',
          channelDescription: 'Fees due, overdue fees and backup reminders',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(r.body),
        ),
      );
      await _plugin.zonedSchedule(
        r.id,
        r.title,
        r.body,
        tz.TZDateTime.from(r.when, tz.UTC),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }
}
