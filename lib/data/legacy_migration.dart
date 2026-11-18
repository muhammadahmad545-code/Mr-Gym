import 'package:drift/drift.dart';

import '../domain/dates.dart';
import 'db.dart';
import 'ids.dart';

/// Moves a 1.x database (schema 4: organisations, locations, risk scores, follow-ups…) to the
/// single-gym schema 5. Members, check-ins, the gym name and currency are kept; the rest of the
/// 1.x tables held derived or unused data and are dropped.
///
/// 1.x never recorded payments, so every member is treated as paid up to their next fee date.
Future<void> migrateLegacyDatabase(AppDatabase db, Migrator m) async {
  final tables = {
    for (final r in await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get())
      r.read<String>('name'),
  }..removeWhere((t) => t.startsWith('sqlite_') || t.startsWith('android_'));

  Future<List<Map<String, Object?>>> rows(String table) async {
    if (!tables.contains(table)) return const [];
    final result = await db.customSelect('SELECT * FROM "$table"').get();
    return [for (final r in result) r.data];
  }

  final oldMembers = await rows('members');
  final oldEvents = await rows('attendance_events');
  final oldMemberships = await rows('memberships');
  final oldOrgs = await rows('organizations');

  for (final t in tables) {
    await db.customStatement('DROP TABLE IF EXISTS "$t"');
  }
  await m.createAll();

  final now = DateTime.now();
  final todayDate = today();

  // Latest known price per member from 1.x memberships.
  final prices = <String, double>{};
  final priceDates = <String, DateTime>{};
  for (final ms in oldMemberships) {
    final memberId = ms['member_id']?.toString();
    final price = (ms['price_amount'] as num?)?.toDouble();
    if (memberId == null || price == null) continue;
    final at = legacyDate(ms['start_at']) ?? DateTime(1970);
    if (priceDates[memberId] == null || at.isAfter(priceDates[memberId]!)) {
      prices[memberId] = price;
      priceDates[memberId] = at;
    }
  }

  final memberIds = <String>{};
  await db.batch((b) {
    for (final row in oldMembers) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final name = [row['first_name'], row['last_name']]
          .whereType<Object>()
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .join(' ');
      final joined = dateOnly(legacyDate(row['joined_at']) ?? legacyDate(row['created_at']) ?? now);
      final feeDay = (row['fee_day'] as num?)?.toInt();
      final anchor = (feeDay != null && feeDay >= 1 && feeDay <= 31) ? feeDay : joined.day;
      final due = nextCycleDate(joined, todayDate, anchorDay: anchor);
      final status = row['status']?.toString() == 'active' ? 'active' : 'inactive';
      memberIds.add(id);
      b.insert(
        db.members,
        MembersCompanion.insert(
          id: id,
          name: name.isEmpty ? 'Member' : name,
          phone: Value(row['phone']?.toString() ?? ''),
          notes: Value(row['notes']?.toString() ?? ''),
          fee: Value(prices[id] ?? 0),
          joinedOn: ymd(joined),
          cycleDay: anchor,
          nextDue: ymd(due),
          status: Value(status),
          createdAt: legacyDate(row['created_at']) ?? now,
          updatedAt: now,
        ),
      );
    }

    final seen = <String>{};
    for (final e in oldEvents) {
      final memberId = e['member_id']?.toString();
      if (memberId == null || !memberIds.contains(memberId)) continue;
      final at = legacyDate(e['occurred_at_utc']) ?? legacyDate(e['occurred_at_local']);
      final day = e['local_date']?.toString() ?? (at == null ? null : ymd(at.toLocal()));
      if (day == null || tryParseYmd(day) == null || !seen.add('$memberId|$day')) continue;
      b.insert(
        db.checkins,
        CheckinsCompanion.insert(id: newId(), memberId: memberId, day: day, at: at ?? parseYmd(day)),
      );
    }

    if (oldOrgs.isNotEmpty) {
      final name = oldOrgs.first['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) b.insert(db.kv, KvCompanion.insert(key: 'gym.name', value: name));
      final currency = oldOrgs.first['default_currency']?.toString().trim() ?? '';
      if (currency.isNotEmpty) {
        b.insert(db.kv, KvCompanion.insert(key: 'gym.currency', value: currency == 'PKR' ? 'Rs' : currency));
      }
    }
  });

  final monthly = prices.values.isEmpty ? 0.0 : prices.values.first;
  await db.batch((b) {
    for (final plan in defaultPlans(monthly)) {
      b.insert(db.plans, plan);
    }
  });
}

/// The starter plans every new gym gets.
List<PlansCompanion> defaultPlans(double monthlyFee) => [
      PlansCompanion.insert(id: newId(), name: 'Monthly', months: const Value(1), price: Value(monthlyFee), sortOrder: const Value(0)),
      PlansCompanion.insert(id: newId(), name: 'Quarterly', months: const Value(3), price: Value(monthlyFee * 3), sortOrder: const Value(1)),
      PlansCompanion.insert(id: newId(), name: 'Half-yearly', months: const Value(6), price: Value(monthlyFee * 6), sortOrder: const Value(2)),
      PlansCompanion.insert(id: newId(), name: 'Yearly', months: const Value(12), price: Value(monthlyFee * 12), sortOrder: const Value(3)),
    ];

/// Drift 1.x stored dates as Unix seconds; also accept ISO text.
DateTime? legacyDate(Object? v) {
  if (v == null) return null;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v * 1000);
  if (v is num) return DateTime.fromMillisecondsSinceEpoch((v * 1000).round());
  final s = v.toString();
  final asInt = int.tryParse(s);
  if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt * 1000);
  return DateTime.tryParse(s)?.toLocal();
}
