import 'package:intl/intl.dart';

import '../data/db.dart';
import 'dates.dart';

/// Members due within this many days count as "due this week".
const dueSoonDays = 7;

enum MemberFilter { all, active, due, overdue, frozen, inactive }

extension MemberFilterLabel on MemberFilter {
  String get label => switch (this) {
        MemberFilter.all => 'All',
        MemberFilter.active => 'Active',
        MemberFilter.due => 'Due',
        MemberFilter.overdue => 'Overdue',
        MemberFilter.frozen => 'Frozen',
        MemberFilter.inactive => 'Inactive',
      };
}

/// A member plus everything derived from their dates, as of [today].
class MemberView {
  MemberView(this.member, DateTime today)
      : today = dateOnly(today),
        due = tryParseYmd(member.nextDue) ?? dateOnly(today);

  final Member member;
  final DateTime today;
  final DateTime due;

  String get id => member.id;
  String get name => member.name;
  bool get isInactive => member.status != 'active';
  bool get isFrozen => !isInactive && member.frozenSince != null;

  /// Active and not frozen: fees are counted for this member.
  bool get isBillable => !isInactive && !isFrozen;
  int get daysUntilDue => daysBetween(today, due);
  bool get isOverdue => isBillable && daysUntilDue < 0;
  bool get isDueToday => isBillable && daysUntilDue == 0;
  bool get isDueSoon => isBillable && daysUntilDue >= 0 && daysUntilDue <= dueSoonDays;
  DateTime get paidUntil => addDays(due, -1);
  DateTime? get birthday => tryParseYmd(member.birthday);
  DateTime? get frozenSince => tryParseYmd(member.frozenSince);

  bool matches(MemberFilter f) => switch (f) {
        MemberFilter.all => true,
        MemberFilter.active => isBillable,
        MemberFilter.due => isDueSoon,
        MemberFilter.overdue => isOverdue,
        MemberFilter.frozen => isFrozen,
        MemberFilter.inactive => isInactive,
      };

  bool matchesQuery(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return true;
    if (member.name.toLowerCase().contains(query)) return true;
    final digits = query.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 3 && member.phone.replaceAll(RegExp(r'\D'), '').contains(digits);
  }

  /// One short line describing where the member stands.
  String get statusLine {
    if (isInactive) return 'Inactive';
    if (isFrozen) return 'Frozen since ${shortDate(frozenSince ?? today)}';
    final d = daysUntilDue;
    if (d < 0) return 'Overdue by ${-d} ${-d == 1 ? 'day' : 'days'}';
    if (d == 0) return 'Due today';
    if (d == 1) return 'Due tomorrow';
    if (d <= dueSoonDays) return 'Due in $d days';
    return 'Paid until ${shortDate(paidUntil)}';
  }

  String get badge {
    if (isInactive) return 'Inactive';
    if (isFrozen) return 'Frozen';
    if (isOverdue) return 'Overdue';
    if (isDueSoon) return 'Due';
    return 'Paid';
  }
}

String shortDate(DateTime d) => DateFormat('d MMM').format(d);
String longDate(DateTime d) => DateFormat('d MMM yyyy').format(d);

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

/// Amount with the gym's currency symbol, e.g. "Rs 3,000".
String formatMoney(String symbol, double amount) {
  final n = NumberFormat(amount == amount.roundToDouble() ? '#,##0' : '#,##0.00').format(amount);
  return symbol.isEmpty ? n : '$symbol $n';
}

String monthsLabel(int months) => switch (months) {
      1 => '1 month',
      12 => '1 year',
      _ => '$months months',
    };
