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
import 'check_in_screen.dart';
import 'common.dart';
import 'live.dart';
import 'member_detail_screen.dart';
import 'member_editor_screen.dart';

class _HomeData {
  _HomeData({required this.members, required this.checkins, required this.revenue, required this.payments});

  final List<MemberView> members;
  final List<Checkin> checkins;
  final double revenue;
  final int payments;

  late final byId = {for (final m in members) m.id: m};
  late final overdue = members.where((m) => m.isOverdue).toList()..sort((a, b) => a.due.compareTo(b.due));
  late final dueSoon = members.where((m) => m.isDueSoon).toList()..sort((a, b) => a.due.compareTo(b.due));
  late final birthdays = () {
    final list = members.where((m) => !m.isInactive && m.birthday != null).toList()
      ..retainWhere((m) => daysBetween(m.today, nextBirthday(m.birthday!, m.today)) <= 7)
      ..sort((a, b) => nextBirthday(a.birthday!, a.today).compareTo(nextBirthday(b.birthday!, b.today)));
    return list;
  }();
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static Future<_HomeData> _load(GymRepository repo) async {
    final now = DateTime.now();
    final t = dateOnly(now);
    final members = [for (final m in await repo.members()) MemberView(m, now)];
    final checkins = await repo.checkinsOn(t);
    final pays = await repo.paymentsBetween(DateTime(t.year, t.month), DateTime(t.year, t.month + 1));
    return _HomeData(
      members: members,
      checkins: checkins,
      revenue: pays.fold<double>(0, (sum, p) => sum + p.amount),
      payments: pays.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ValueListenableBuilder(
      valueListenable: app.gym,
      builder: (context, gym, _) => Live<_HomeData>(
        load: (repo) => _load(repo),
        builder: (context, d) => BPage(
          title: gym.name,
          subtitle: DateFormat('EEEE, d MMMM').format(DateTime.now()),
          children: [
            const UpdateCard(),
            BButton(
              label: 'Mark attendance',
              icon: Icons.how_to_reg_rounded,
              expand: true,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckInScreen())),
            ),
            const SizedBox(height: Gap.md),
            _tiles(context, d),
            if (d.members.isEmpty)
              BEmptyState(
                icon: Icons.person_add_alt_1_rounded,
                title: 'Add your first member',
                message: 'Members you add show up here with their fees and attendance.',
                actionLabel: 'Add member',
                onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MemberEditorScreen())),
              ),
            if (d.overdue.isNotEmpty) ..._memberSection(context, 'Overdue', d.overdue, MemberFilter.overdue),
            if (d.dueSoon.isNotEmpty) ..._memberSection(context, 'Due this week', d.dueSoon, MemberFilter.due),
            if (d.birthdays.isNotEmpty) ..._birthdays(context, d.birthdays),
            if (d.checkins.isNotEmpty) ..._checkins(context, d),
          ],
        ),
      ),
    );
  }

  Widget _tiles(BuildContext context, _HomeData d) {
    final app = context.app;
    final p = context.basalt;
    void openMembers(MemberFilter f) {
      app.memberFilter.value = f;
      app.tabs.index = 1;
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: BStatTile(
                label: 'Check-ins today',
                value: '${d.checkins.length}',
                icon: Icons.how_to_reg_rounded,
                color: p.accent,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckInScreen())),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: BStatTile(
                label: 'Due this week',
                value: '${d.dueSoon.length}',
                icon: Icons.event_rounded,
                color: p.warning,
                onTap: () => openMembers(MemberFilter.due),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        Row(
          children: [
            Expanded(
              child: BStatTile(
                label: 'Overdue',
                value: '${d.overdue.length}',
                icon: Icons.error_outline_rounded,
                color: p.danger,
                onTap: () => openMembers(MemberFilter.overdue),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: BStatTile(
                label: 'Revenue this month',
                value: app.money(d.revenue),
                icon: Icons.payments_outlined,
                color: p.success,
                hint: '${d.payments} ${d.payments == 1 ? 'payment' : 'payments'}',
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _memberSection(BuildContext context, String title, List<MemberView> list, MemberFilter filter) {
    final app = context.app;
    return [
      BSectionTitle(
        title,
        action: list.length > 5 ? 'See all ${list.length}' : null,
        onAction: () {
          app.memberFilter.value = filter;
          app.tabs.index = 1;
        },
      ),
      BGroup(
        children: [
          for (final m in list.take(5))
            BListRow(
              leading: Avatar(m.name, size: 36, color: statusColor(context, m)),
              title: m.name,
              subtitle: '${m.statusLine} · ${app.money(m.member.fee)}',
              onTap: () => openMember(context, m.id),
              trailing: IconButton(
                tooltip: 'Remind ${m.name} on WhatsApp',
                icon: const Icon(Icons.chat_outlined),
                onPressed: () => attempt(
                  context,
                  () => Contact.whatsApp(
                    phone: m.member.phone,
                    countryCode: app.gym.value.countryCode,
                    message: Messages.feeReminder(gym: app.gym.value.name, m: m, amount: app.money(m.member.fee)),
                  ),
                ),
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _birthdays(BuildContext context, List<MemberView> list) {
    final app = context.app;
    return [
      const BSectionTitle('Birthdays this week'),
      BGroup(
        children: [
          for (final m in list)
            () {
              final days = daysBetween(m.today, nextBirthday(m.birthday!, m.today));
              return BListRow(
                icon: Icons.cake_outlined,
                title: m.name,
                subtitle: days == 0 ? 'Today' : (days == 1 ? 'Tomorrow' : DateFormat('EEEE, d MMM').format(nextBirthday(m.birthday!, m.today))),
                onTap: () => openMember(context, m.id),
                trailing: IconButton(
                  tooltip: 'Wish ${m.name} on WhatsApp',
                  icon: const Icon(Icons.chat_outlined),
                  onPressed: () => attempt(
                    context,
                    () => Contact.whatsApp(
                      phone: m.member.phone,
                      countryCode: app.gym.value.countryCode,
                      message: Messages.birthday(gym: app.gym.value.name, member: m.name),
                    ),
                  ),
                ),
              );
            }(),
        ],
      ),
    ];
  }

  List<Widget> _checkins(BuildContext context, _HomeData d) {
    final time = DateFormat('h:mm a');
    return [
      const BSectionTitle("Today's check-ins"),
      BGroup(
        children: [
          for (final c in d.checkins.take(20))
            BListRow(
              leading: Avatar(d.byId[c.memberId]?.name ?? '?', size: 36),
              title: d.byId[c.memberId]?.name ?? 'Deleted member',
              subtitle: time.format(c.at),
              dense: true,
              onTap: d.byId[c.memberId] == null ? null : () => openMember(context, c.memberId),
            ),
        ],
      ),
    ];
  }
}

void openMember(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemberDetailScreen(memberId: id)));
