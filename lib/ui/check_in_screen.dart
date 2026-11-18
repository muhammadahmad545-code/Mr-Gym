import 'package:basalt/basalt.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../domain/dates.dart';
import '../domain/member_view.dart';
import 'common.dart';
import 'live.dart';

class _CheckInData {
  const _CheckInData(this.members, this.checkedIn);
  final List<MemberView> members;
  final Set<String> checkedIn;
}

/// Front-desk attendance: search a member and tap to check them in for today.
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  String _query = '';

  Future<void> _checkIn(MemberView m, bool already) async {
    final app = context.app;
    if (already) {
      BToast.show(
        context,
        '${m.name} already checked in today',
        actionLabel: 'Undo',
        onAction: () => app.repo.undoCheckIn(m.id, today()),
      );
      return;
    }
    final ok = await attempt(context, () => app.repo.checkIn(m.id));
    if (ok == null || !mounted) return;
    final extra = m.isOverdue ? ' · fee overdue by ${-m.daysUntilDue} days' : (m.isFrozen ? ' · membership is frozen' : '');
    BToast.show(context, '${m.name} checked in$extra', actionLabel: 'Undo', onAction: () => app.repo.undoCheckIn(m.id, today()));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.basalt;
    return Scaffold(
      appBar: AppBar(title: const Text('Mark attendance')),
      body: Live<_CheckInData>(
        load: (repo) async {
          final now = DateTime.now();
          final members = [for (final m in await repo.members()) MemberView(m, now)]..removeWhere((m) => m.isInactive);
          final checkins = await repo.checkinsOn(dateOnly(now));
          return _CheckInData(members, {for (final c in checkins) c.memberId});
        },
        builder: (context, d) {
          final list = d.members.where((m) => m.matchesQuery(_query)).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.sm),
                child: BSearchField(hint: 'Search name or phone', autofocus: true, onChanged: (v) => setState(() => _query = v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.sm),
                child: Row(
                  children: [
                    Text('${d.checkedIn.length} checked in today', style: BasaltType.caption.copyWith(color: p.textMuted)),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? BEmptyState(
                        icon: Icons.search_off_rounded,
                        title: d.members.isEmpty ? 'No active members yet' : 'No member matches "$_query"',
                      )
                    : ListView.separated(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.only(bottom: Gap.xxl),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => Divider(height: 1, indent: 68, color: p.border),
                        itemBuilder: (context, i) {
                          final m = list[i];
                          final done = d.checkedIn.contains(m.id);
                          return BListRow(
                            leading: Avatar(m.name, color: statusColor(context, m)),
                            title: m.name,
                            subtitle: m.statusLine,
                            onTap: () => _checkIn(m, done),
                            trailing: done
                                ? BBadge('Checked in', color: p.success)
                                : Icon(Icons.add_circle_outline_rounded, color: p.accent, semanticLabel: 'Check in ${m.name}'),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
