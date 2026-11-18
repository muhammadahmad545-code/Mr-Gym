import 'dates.dart';
import 'member_view.dart';

/// WhatsApp message texts. The owner presses Send in WhatsApp.
abstract final class Messages {
  static String feeReminder({required String gym, required MemberView m, required String amount}) {
    final first = m.name.split(' ').first;
    if (m.isOverdue) {
      return 'Assalam-o-Alaikum $first,\n\nA friendly reminder from $gym: your fee of $amount was due on ${longDate(m.due)}. '
          'Please clear it at your next visit.\n\nThank you,\n$gym';
    }
    final when = m.isDueToday ? 'today' : 'on ${longDate(m.due)}';
    return 'Assalam-o-Alaikum $first,\n\nA friendly reminder from $gym: your fee of $amount is due $when.\n\nThank you,\n$gym';
  }

  static String receipt({
    required String gym,
    required String member,
    required String amount,
    required DateTime paidAt,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    return 'Payment receipt: $gym\n\n'
        'Member: $member\n'
        'Amount: $amount\n'
        'Paid on: ${longDate(paidAt)}\n'
        'Covers: ${longDate(periodStart)} to ${longDate(addDays(periodEnd, -1))}\n\n'
        'Thank you!';
  }

  static String birthday({required String gym, required String member}) {
    final first = member.split(' ').first;
    return 'Happy birthday $first! Wishing you a great year ahead from all of us at $gym.';
  }
}
