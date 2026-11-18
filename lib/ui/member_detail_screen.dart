import 'package:basalt/basalt.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_services.dart';
import '../data/db.dart';
import '../data/gym_repository.dart';
import '../domain/dates.dart';
import '../domain/member_view.dart';
import '../domain/messages.dart';
import '../services/contact.dart';
import 'common.dart';
import 'live.dart';
import 'member_editor_screen.dart';
import 'payment_sheet.dart';

class _Detail {
  const _Detail({
    required this.view,
    required this.payments,
    required this.checkins,
    required this.planName,
    required this.visitsThisMonth,
  });

  final MemberView? view;
  final List<Payment> payments;
  final List<Checkin> checkins;
  final String? planName;
  final int visitsThisMonth;

  bool get checkedInToday => checkins.isNotEmpty && checkins.first.day == ymd(today());
}

class MemberDetailScreen extends StatelessWidget {
  const MemberDetailScreen({super.key, required this.memberId});

  final String memberId;

  Future<_Detail> _load(GymRepository repo) async {
    final m = await repo.member(memberId);
    if (m == null) return const _Detail(view: null, payments: [], checkins: [], planName: null, visitsThisMonth: 0);
    final now = DateTime.now();
    final plans = await repo.plans();
    return _Detail(
      view: MemberView(m, now),
      payments: await repo.paymentsFor(memberId),
      checkins: await repo.checkinsFor(memberId),
      planName: plans.where((p) => p.id == m.planId).firstOrNull?.name,
      visitsThisMonth: await repo.checkinCountFor(memberId, from: DateTime(now.year, now.month)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Live<_Detail>(
      load: _load,
      builder: (context, d) {
        final m = d.view;
        if (m == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const BEmptyState(icon: Icons.person_off_outlined, title: 'This member was deleted'),
          );
        }
        return Scaffold(
          appBar: AppBar(actions: [_menu(context, m)]),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xxl),
            children: [
              _header(context, m, d),
              const SizedBox(height: Gap.lg),
              _actions(context, m, d),
              if (m.isOverdue || m.isFrozen || m.isInactive) ...[const SizedBox(height: Gap.md), _notice(context, m)],
              const BSectionTitle('Membership'),
              _membership(context, m, d),
              ..._payments(context, m, d),
              ..._attendance(context, m, d),
              const BSectionTitle('Notes'),
              _notes(context, m),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, MemberView m, _Detail d) {
    final p = context.basalt;
    final color = statusColor(context, m);
    return Row(
      children: [
        Avatar(m.name, size: 60, color: color),
        const SizedBox(width: Gap.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.name, style: BasaltType.display.copyWith(color: p.text, fontSize: 24)),
              if (m.member.phone.isNotEmpty)
                Text(m.member.phone, style: BasaltType.body.copyWith(color: p.textMuted)),
              const SizedBox(height: Gap.xs + 2),
              Wrap(
                spacing: Gap.xs + 2,
                runSpacing: Gap.xs,
                children: [
                  BBadge(m.badge, color: color),
                  if (d.planName != null) BBadge(d.planName!, color: p.textMuted),
                  if (d.checkedInToday) BBadge('Checked in today', color: p.success),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actions(BuildContext context, MemberView m, _Detail d) {
    final app = context.app;
    Widget action(IconData icon, String label, VoidCallback? onTap) => Expanded(
          child: BCard(
            onTap: onTap,
            semanticLabel: label,
            padding: const EdgeInsets.symmetric(vertical: Gap.md, horizontal: Gap.xs),
            child: Column(
              children: [
                Icon(icon, color: onTap == null ? context.basalt.textFaint : context.basalt.accent),
                const SizedBox(height: Gap.xs),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: BasaltType.caption.copyWith(color: context.basalt.text, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        );
    final hasPhone = m.member.phone.isNotEmpty;
    return Row(
      children: [
        action(
          d.checkedInToday ? Icons.check_circle_rounded : Icons.how_to_reg_rounded,
          d.checkedInToday ? 'Checked in' : 'Check in',
          m.isInactive
              ? null
              : () async {
                  if (d.checkedInToday) {
                    final undo = await bConfirm(context, title: "Undo today's check-in?", confirmLabel: 'Undo');
                    if (undo) await app.repo.undoCheckIn(m.id, today());
                    return;
                  }
                  final ok = await attempt(context, () => app.repo.checkIn(m.id));
                  if (ok == true && context.mounted) BToast.show(context, '${m.name} checked in');
                },
        ),
        const SizedBox(width: Gap.sm),
        action(Icons.payments_outlined, 'Record payment', () => showPaymentSheet(context, m)),
        const SizedBox(width: Gap.sm),
        action(
          Icons.chat_outlined,
          'WhatsApp',
          hasPhone
              ? () => attempt(
                    context,
                    () => Contact.whatsApp(
                      phone: m.member.phone,
                      countryCode: app.gym.value.countryCode,
                      message: m.isBillable && (m.isOverdue || m.isDueSoon)
                          ? Messages.feeReminder(gym: app.gym.value.name, m: m, amount: app.money(m.member.fee))
                          : '',
                    ),
                  )
              : null,
        ),
        const SizedBox(width: Gap.sm),
        action(Icons.call_outlined, 'Call', hasPhone ? () => attempt(context, () => Contact.call(m.member.phone)) : null),
      ],
    );
  }

  Widget _notice(BuildContext context, MemberView m) {
    final p = context.basalt;
    final app = context.app;
    if (m.isInactive) {
      return BCard(
        child: Row(
          children: [
            Expanded(child: Text('This member has left. Reactivate them to check in or track fees.', style: BasaltType.body.copyWith(color: p.textMuted, fontSize: 14))),
            BButton(label: 'Reactivate', variant: BButtonVariant.secondary, onPressed: () => app.repo.setActive(m.id, true)),
          ],
        ),
      );
    }
    if (m.isFrozen) {
      final days = daysBetween(m.frozenSince ?? m.today, m.today);
      return BCard(
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Frozen for $days ${days == 1 ? 'day' : 'days'}. Unfreezing moves the due date on by the frozen days.',
                style: BasaltType.body.copyWith(color: p.textMuted, fontSize: 14),
              ),
            ),
            const SizedBox(width: Gap.sm),
            BButton(
              label: 'Unfreeze',
              variant: BButtonVariant.secondary,
              onPressed: () async {
                final moved = await attempt(context, () => app.repo.unfreeze(m.id));
                if (moved != null && context.mounted) BToast.show(context, 'Unfrozen. Due date moved by $moved days.');
              },
            ),
          ],
        ),
      );
    }
    return BCard(
      borderColor: p.danger.withValues(alpha: 0.4),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: p.danger),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              '${m.statusLine}. ${app.money(m.member.fee)} was due on ${longDate(m.due)}.',
              style: BasaltType.body.copyWith(color: p.text, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _membership(BuildContext context, MemberView m, _Detail d) {
    final app = context.app;
    return BCard(
      child: Column(
        children: [
          InfoLine('Plan', d.planName ?? 'Custom'),
          InfoLine('Fee', '${app.money(m.member.fee)} / ${monthsLabel(m.member.planMonths)}'),
          if (!m.isInactive) InfoLine('Next fee due', longDate(m.due), valueColor: statusColor(context, m)),
          InfoLine('Paid until', longDate(m.paidUntil)),
          InfoLine('Joined', longDate(tryParseYmd(m.member.joinedOn) ?? m.today)),
          if (m.birthday != null) InfoLine('Birthday', DateFormat('d MMMM').format(m.birthday!)),
        ],
      ),
    );
  }

  List<Widget> _payments(BuildContext context, MemberView m, _Detail d) {
    final app = context.app;
    return [
      BSectionTitle('Payments', action: 'Record payment', onAction: () => showPaymentSheet(context, m)),
      if (d.payments.isEmpty)
        BCard(child: Text('No payments recorded yet.', style: BasaltType.body.copyWith(color: context.basalt.textMuted)))
      else
        BGroup(
          children: [
            for (final (i, pay) in d.payments.take(24).indexed)
              BListRow(
                icon: Icons.receipt_long_outlined,
                iconColor: context.basalt.success,
                title: app.money(pay.amount),
                subtitle: 'Paid ${longDate(pay.paidAt)} · ${shortDate(parseYmd(pay.periodStart))} – '
                    '${shortDate(addDays(parseYmd(pay.periodEnd), -1))}${pay.note.isEmpty ? '' : ' · ${pay.note}'}',
                chevron: true,
                onTap: () => _paymentActions(context, m, pay, latest: i == 0),
              ),
          ],
        ),
    ];
  }

  Future<void> _paymentActions(BuildContext context, MemberView m, Payment pay, {required bool latest}) async {
    final app = context.app;
    final choice = await showSheet<String>(
      context,
      title: app.money(pay.amount),
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BButton(
            label: 'Send receipt on WhatsApp',
            icon: Icons.chat_outlined,
            onPressed: m.member.phone.isEmpty ? null : () => Navigator.pop(ctx, 'receipt'),
          ),
          const SizedBox(height: Gap.sm),
          if (latest)
            BButton(
              label: 'Undo this payment',
              variant: BButtonVariant.danger,
              onPressed: () => Navigator.pop(ctx, 'undo'),
            )
          else
            Text('Only the latest payment can be undone.', style: BasaltType.caption.copyWith(color: ctx.basalt.textFaint)),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'receipt') await sendReceipt(context, app, m.member, pay);
    if (choice == 'undo') {
      final ok = await bConfirm(
        context,
        title: 'Undo this payment?',
        message: 'The payment is removed and the due date goes back to ${longDate(parseYmd(pay.previousDue))}.',
        confirmLabel: 'Undo payment',
        danger: true,
      );
      if (ok && context.mounted) await attempt(context, () => app.repo.undoPayment(pay.id));
    }
  }

  List<Widget> _attendance(BuildContext context, MemberView m, _Detail d) {
    final p = context.basalt;
    final last = d.checkins.isEmpty ? null : parseYmd(d.checkins.first.day);
    final recent = d.checkins.take(14).toList();
    return [
      const BSectionTitle('Attendance'),
      BCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _metric(context, '${d.visitsThisMonth}', 'Visits this month')),
                Expanded(
                  child: _metric(
                    context,
                    last == null ? 'Never' : (sameDay(last, m.today) ? 'Today' : '${daysBetween(last, m.today)}d ago'),
                    'Last visit',
                  ),
                ),
              ],
            ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: Gap.md),
              Divider(height: 1, color: p.border),
              const SizedBox(height: Gap.sm),
              for (final c in recent)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.check_rounded, size: 16, color: p.success),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          DateFormat('EEE, d MMM yyyy').format(parseYmd(c.day)),
                          style: BasaltType.body.copyWith(color: p.text, fontSize: 14),
                        ),
                      ),
                      Text(DateFormat('h:mm a').format(c.at), style: BasaltType.caption.copyWith(color: p.textMuted)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _metric(BuildContext context, String value, String label) {
    final p = context.basalt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: BasaltType.title.copyWith(color: p.text)),
        Text(label, style: BasaltType.caption.copyWith(color: p.textMuted)),
      ],
    );
  }

  Widget _notes(BuildContext context, MemberView m) {
    final p = context.basalt;
    final app = context.app;
    return BCard(
      onTap: () async {
        final controller = TextEditingController(text: m.member.notes);
        final saved = await showSheet<bool>(
          context,
          title: 'Notes',
          builder: (ctx) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Goals, health notes, trainer…'),
              ),
              const SizedBox(height: Gap.lg),
              BButton(label: 'Save notes', expand: true, onPressed: () => Navigator.pop(ctx, true)),
            ],
          ),
        );
        if (saved == true) await app.repo.updateNotes(m.id, controller.text);
      },
      child: Row(
        children: [
          Expanded(
            child: Text(
              m.member.notes.isEmpty ? 'Add a note' : m.member.notes,
              style: BasaltType.body.copyWith(color: m.member.notes.isEmpty ? p.textFaint : p.text),
            ),
          ),
          Icon(Icons.edit_outlined, size: 18, color: p.textFaint),
        ],
      ),
    );
  }

  Widget _menu(BuildContext context, MemberView m) {
    final app = context.app;
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemberEditorScreen(member: m.member)));
          case 'freeze':
            final ok = await bConfirm(
              context,
              title: 'Freeze membership?',
              message: 'Use this when ${m.name} takes a break. No fees are counted while frozen, and the due date moves on by the frozen days when you unfreeze.',
              confirmLabel: 'Freeze',
            );
            if (ok && context.mounted) await attempt(context, () => app.repo.freeze(m.id));
          case 'unfreeze':
            final moved = await attempt(context, () => app.repo.unfreeze(m.id));
            if (moved != null && context.mounted) BToast.show(context, 'Unfrozen. Due date moved by $moved days.');
          case 'due':
            final d = await showDatePicker(
              context: context,
              initialDate: m.due,
              firstDate: DateTime(2000),
              lastDate: addDays(today(), 3650),
              helpText: 'Next fee due',
            );
            if (d != null && context.mounted) await attempt(context, () => app.repo.setNextDue(m.id, d));
          case 'leave':
            final ok = await bConfirm(
              context,
              title: 'Mark ${m.name} as left?',
              message: 'They move to Inactive and stop counting towards fees and reminders. History is kept.',
              confirmLabel: 'Mark as left',
            );
            if (ok) await app.repo.setActive(m.id, false);
          case 'reactivate':
            await app.repo.setActive(m.id, true);
          case 'delete':
            final ok = await bConfirm(
              context,
              title: 'Delete ${m.name}?',
              message: 'Their payments and attendance are deleted too. To keep the history, mark them as left instead.',
              confirmLabel: 'Delete',
              danger: true,
            );
            if (ok && context.mounted) {
              await app.repo.deleteMember(m.id);
              if (context.mounted) Navigator.of(context).pop();
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit member')),
        if (!m.isInactive && !m.isFrozen) const PopupMenuItem(value: 'freeze', child: Text('Freeze membership')),
        if (m.isFrozen) const PopupMenuItem(value: 'unfreeze', child: Text('Unfreeze')),
        if (!m.isInactive) const PopupMenuItem(value: 'due', child: Text('Change due date')),
        if (!m.isInactive) const PopupMenuItem(value: 'leave', child: Text('Mark as left')),
        if (m.isInactive) const PopupMenuItem(value: 'reactivate', child: Text('Reactivate')),
        const PopupMenuItem(value: 'delete', child: Text('Delete member')),
      ],
    );
  }
}
