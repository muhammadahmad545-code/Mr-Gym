/// Date-only helpers. Calendar dates are stored as `yyyy-MM-dd` text so they never shift
/// with the phone's time zone.
library;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime today() => dateOnly(DateTime.now());

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseYmd(String s) {
  final parts = s.split('-');
  if (parts.length != 3) throw FormatException('Not a date: $s');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

DateTime? tryParseYmd(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    return parseYmd(s);
  } on FormatException {
    return null;
  }
}

/// Whole days from [a] to [b] (calendar days, safe across daylight-saving changes).
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

int lastDayOfMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Adds calendar months, keeping the day of month when it exists and otherwise using the
/// last day of the target month (31 Jan + 1 month = 28/29 Feb). Never "30 days".
DateTime addMonths(DateTime d, int months, {int? anchorDay}) {
  final raw = d.month - 1 + months;
  final year = d.year + (raw >= 0 ? raw ~/ 12 : -((-raw + 11) ~/ 12));
  final month = raw % 12 + 1;
  final day = anchorDay ?? d.day;
  final last = lastDayOfMonth(year, month);
  return DateTime(year, month, day > last ? last : day);
}

/// The first fee date on or after [onOrAfter] (and not before [joined]) for fees that fall on
/// [anchorDay] of each month (default: the joining day).
DateTime nextCycleDate(DateTime joined, DateTime onOrAfter, {int? anchorDay}) {
  final j = dateOnly(joined);
  final t = dateOnly(onOrAfter);
  final from = t.isAfter(j) ? t : j;
  final day = anchorDay ?? j.day;
  final last = lastDayOfMonth(from.year, from.month);
  var c = DateTime(from.year, from.month, day > last ? last : day);
  if (c.isBefore(from)) c = addMonths(c, 1, anchorDay: day);
  return c;
}

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Next occurrence of a birthday (on or after [from]). 29 Feb falls on 28 Feb in other years.
DateTime nextBirthday(DateTime birthday, DateTime from) {
  final f = dateOnly(from);
  DateTime inYear(int y) {
    final last = lastDayOfMonth(y, birthday.month);
    return DateTime(y, birthday.month, birthday.day > last ? last : birthday.day);
  }

  final thisYear = inYear(f.year);
  return thisYear.isBefore(f) ? inYear(f.year + 1) : thisYear;
}
