import 'package:basalt/basalt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../data/db.dart';
import '../domain/dates.dart';
import '../domain/member_view.dart';
import '../domain/messages.dart';
import '../services/contact.dart';
import 'common.dart';

/// Opens the "Record payment" sheet. Offers to send a WhatsApp receipt afterwards.
Future<void> showPaymentSheet(BuildContext context, MemberView m) async {
  final app = context.app;
  final payment = await showSheet<Payment>(
    context,
    title: 'Record payment',
    builder: (_) => _PaymentForm(member: m),
  );
  if (payment == null || !context.mounted) return;
  BToast.show(
    context,
    'Payment saved. Paid until ${shortDate(addDays(parseYmd(payment.periodEnd), -1))}',
    actionLabel: m.member.phone.isEmpty ? null : 'Send receipt',
    onAction: () => sendReceipt(context, app, m.member, payment),
  );
}

Future<void> sendReceipt(BuildContext context, AppServices app, Member member, Payment payment) => attempt(
      context,
      () => Contact.whatsApp(
        phone: member.phone,
        countryCode: app.gym.value.countryCode,
        message: Messages.receipt(
          gym: app.gym.value.name,
          member: member.name,
          amount: app.money(payment.amount),
          paidAt: payment.paidAt,
          periodStart: parseYmd(payment.periodStart),
          periodEnd: parseYmd(payment.periodEnd),
        ),
      ),
    );

class _PaymentForm extends StatefulWidget {
  const _PaymentForm({required this.member});

  final MemberView member;

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  late int _months = widget.member.member.planMonths;
  late final _amount = TextEditingController(text: amountText(_priceFor(_months)));
  final _note = TextEditingController();
  late bool _fromToday = _defaultFromToday;
  bool _amountEdited = false;
  bool _busy = false;

  MemberView get m => widget.member;

  /// Someone more than a month behind usually restarts from today rather than paying the gap.
  bool get _defaultFromToday => m.daysUntilDue < -31;

  double _priceFor(int months) {
    final per = m.member.planMonths <= 0 ? m.member.fee : m.member.fee / m.member.planMonths;
    return double.parse((per * months).toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  DateTime get _start => _fromToday ? today() : m.due;
  DateTime get _end => addMonths(_start, _months, anchorDay: _fromToday ? today().day : m.member.cycleDay);

  Future<void> _save() async {
    final amount = parseAmount(_amount.text);
    if (amount == null || amount < 0) {
      BToast.show(context, 'Enter the amount as a number.');
      return;
    }
    setState(() => _busy = true);
    final repo = context.app.repo;
    final payment = await attempt(
      context,
      () => repo.recordPayment(memberId: m.id, amount: amount, months: _months, fromToday: _fromToday, note: _note.text),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (payment != null) Navigator.of(context).pop(payment);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.basalt;
    final app = context.app;
    final showStart = !sameDay(m.due, today());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(m.name, style: BasaltType.bodyStrong.copyWith(color: p.text)),
        Text(m.statusLine, style: BasaltType.caption.copyWith(color: statusColor(context, m))),
        const SizedBox(height: Gap.lg),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(labelText: 'Amount', prefixText: '${app.gym.value.currency} '),
          onChanged: (_) => _amountEdited = true,
        ),
        const BSectionTitle('Covers'),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final months in {1, 3, 6, 12, m.member.planMonths}.toList()..sort())
              BChip(
                label: monthsLabel(months),
                selected: _months == months,
                onTap: () => setState(() {
                  _months = months;
                  if (!_amountEdited) _amount.text = amountText(_priceFor(months));
                }),
              ),
          ],
        ),
        if (showStart) ...[
          const BSectionTitle('Starts from'),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              BChip(label: 'Due date (${shortDate(m.due)})', selected: !_fromToday, onTap: () => setState(() => _fromToday = false)),
              BChip(label: 'Today', selected: _fromToday, onTap: () => setState(() => _fromToday = true)),
            ],
          ),
        ],
        const SizedBox(height: Gap.md),
        Container(
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(color: p.fill, borderRadius: BorderRadius.circular(Radii.md)),
          child: Text(
            'Covers ${longDate(_start)} to ${longDate(addDays(_end, -1))}. Next fee due ${longDate(_end)}.',
            style: BasaltType.caption.copyWith(color: p.textMuted),
          ),
        ),
        const SizedBox(height: Gap.md),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. cash, bank transfer'),
        ),
        const SizedBox(height: Gap.lg),
        BButton(label: 'Save payment', onPressed: _save, busy: _busy, expand: true),
      ],
    );
  }
}
