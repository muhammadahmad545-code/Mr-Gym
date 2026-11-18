import 'package:basalt/basalt.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../domain/member_view.dart';
import 'common.dart';
import 'home_screen.dart';
import 'live.dart';
import 'member_editor_screen.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = context.basalt;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MemberEditorScreen())),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add member'),
      ),
      body: SafeArea(
        bottom: false,
        child: Live<List<MemberView>>(
          load: (repo) async {
            final now = DateTime.now();
            return [for (final m in await repo.members()) MemberView(m, now)];
          },
          builder: (context, members) => ValueListenableBuilder(
            valueListenable: app.memberFilter,
            builder: (context, filter, _) {
              final counts = {for (final f in MemberFilter.values) f: members.where((m) => m.matches(f)).length};
              final list = members.where((m) => m.matches(filter) && m.matchesQuery(_query)).toList();
              if (filter == MemberFilter.overdue || filter == MemberFilter.due) list.sort((a, b) => a.due.compareTo(b.due));
              return Column(
                children: [
                  BHeader(
                    title: 'Members',
                    subtitle: '${counts[MemberFilter.active]} active · ${members.length} total',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                    child: BSearchField(
                      controller: _search,
                      hint: 'Search name or phone',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
                      children: [
                        for (final f in MemberFilter.values)
                          Padding(
                            padding: const EdgeInsets.only(right: Gap.sm),
                            child: BChip(
                              label: '${f.label} ${counts[f]}',
                              selected: f == filter,
                              color: switch (f) {
                                MemberFilter.overdue => p.danger,
                                MemberFilter.due => p.warning,
                                _ => null,
                              },
                              onTap: () => app.memberFilter.value = f,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: list.isEmpty
                        ? SingleChildScrollView(
                            child: BEmptyState(
                              icon: members.isEmpty ? Icons.people_outline_rounded : Icons.search_off_rounded,
                              title: members.isEmpty
                                  ? 'No members yet'
                                  : (_query.isEmpty ? 'Nobody here' : 'No member matches "$_query"'),
                              message: members.isEmpty ? 'Tap "Add member" to add your first member.' : null,
                            ),
                          )
                        : ListView.separated(
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.only(bottom: 96),
                            itemCount: list.length,
                            separatorBuilder: (_, _) => Divider(height: 1, indent: 68, color: p.border),
                            itemBuilder: (context, i) {
                              final m = list[i];
                              final color = statusColor(context, m);
                              return BListRow(
                                leading: Avatar(m.name, color: color),
                                title: m.name,
                                subtitle: [if (m.member.phone.isNotEmpty) m.member.phone, m.statusLine].join(' · '),
                                trailing: BBadge(m.badge, color: color),
                                onTap: () => openMember(context, m.id),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
