import 'package:basalt/basalt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../data/db.dart';
import '../domain/dates.dart';
import '../domain/member_view.dart';
import 'common.dart';

/// Add a member, or edit one when [member] is given.
class MemberEditorScreen extends StatefulWidget {
  const MemberEditorScreen({super.key, this.member});

  final Member? member;

  @override
  State<MemberEditorScreen> createState() => _MemberEditorScreenState();
}

class _MemberEditorScreenState extends State<MemberEditorScreen> {
  late final _name = TextEditingController(text: widget.member?.name ?? '');
  late final _phone = TextEditingController(text: widget.member?.phone ?? '');
  late final _fee = TextEditingController(text: widget.member == null ? '' : amountText(widget.member!.fee));
  late final _notes = TextEditingController(text: widget.member?.notes ?? '');
  late DateTime _joined = tryParseYmd(widget.member?.joinedOn) ?? today();
  late DateTime? _birthday = tryParseYmd(widget.member?.birthday);
  late String? _planId = widget.member?.planId;
  late int _months = widget.member?.planMonths ?? 1;
  bool _paidNow = true;
  bool _busy = false;
  String? _nameError;
  List<Plan>? _plans;

  bool get _isNew => widget.member == null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_plans == null) _loadPlans();
  }

  Future<void> _loadPlans() async {
    final plans = await context.app.repo.plans();
    if (!mounted) return;
    setState(() {
      _plans = plans;
      if (_isNew && plans.isNotEmpty) _pickPlan(plans.first);
    });
  }

  void _pickPlan(Plan? plan) {
    _planId = plan?.id;
    if (plan != null) {
      _months = plan.months;
      _fee.text = amountText(plan.price);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _fee.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDate(DateTime? initial, {required DateTime first, required DateTime last, String? help}) {
    return showDatePicker(
      context: context,
      initialDate: initial ?? today(),
      firstDate: first,
      lastDate: last,
      helpText: help,
    );
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Enter a name');
      return;
    }
    final fee = parseAmount(_fee.text);
    if (fee == null || fee < 0) {
      BToast.show(context, 'Enter the fee as a number.');
      return;
    }
    setState(() => _busy = true);
    final repo = context.app.repo;
    final saved = await attempt(context, () async {
      if (_isNew) {
        return repo.addMember(
          name: _name.text,
          phone: _phone.text,
          notes: _notes.text,
          birthday: _birthday,
          planId: _planId,
          fee: fee,
          planMonths: _months,
          joinedOn: _joined,
          paidNow: _paidNow,
        );
      }
      await repo.updateMember(
        widget.member!.id,
        name: _name.text,
        phone: _phone.text,
        notes: _notes.text,
        birthday: _birthday,
        planId: _planId,
        fee: fee,
        planMonths: _months,
        joinedOn: _joined,
      );
      return widget.member!.id;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved != null) {
      Navigator.of(context).pop(saved);
      BToast.show(context, _isNew ? '${_name.text.trim()} added' : 'Changes saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.basalt;
    final app = context.app;
    final plans = _plans ?? const <Plan>[];
    return SubPage(
      title: _isNew ? 'Add member' : 'Edit member',
      bottom: BButton(label: _isNew ? 'Save member' : 'Save changes', onPressed: _save, busy: _busy, expand: true),
      children: [
        TextField(
          controller: _name,
          autofocus: _isNew,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: 'Full name', errorText: _nameError),
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        const SizedBox(height: Gap.md),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ \-]'))],
          decoration: const InputDecoration(labelText: 'Phone (WhatsApp)', hintText: 'e.g. 0300 1234567'),
        ),
        const BSectionTitle('Membership plan'),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final plan in plans)
              BChip(
                label: plan.name,
                selected: _planId == plan.id,
                onTap: () => setState(() => _pickPlan(plan)),
              ),
            BChip(label: 'Custom', selected: _planId == null, onTap: () => setState(() => _pickPlan(null))),
          ],
        ),
        const SizedBox(height: Gap.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _fee,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(labelText: 'Fee', prefixText: '${app.gym.value.currency} '),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey(_months),
                initialValue: _months,
                decoration: const InputDecoration(labelText: 'Covers'),
                items: [
                  for (final m in {1, 2, 3, 6, 12, _months})
                    DropdownMenuItem(value: m, child: Text(monthsLabel(m))),
                ],
                onChanged: (v) => setState(() => _months = v ?? _months),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        BGroup(
          children: [
            BListRow(
              icon: Icons.event_available_rounded,
              title: 'Joined',
              subtitle: longDate(_joined),
              chevron: true,
              onTap: () async {
                final d = await _pickDate(_joined, first: DateTime(2000), last: addDays(today(), 365), help: 'Joining date');
                if (d != null) setState(() => _joined = d);
              },
            ),
            BListRow(
              icon: Icons.cake_outlined,
              title: 'Birthday',
              subtitle: _birthday == null ? 'Optional' : longDate(_birthday!),
              chevron: _birthday == null,
              trailing: _birthday == null
                  ? null
                  : IconButton(
                      tooltip: 'Clear birthday',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => setState(() => _birthday = null),
                    ),
              onTap: () async {
                final d = await _pickDate(_birthday ?? DateTime(1995, 1, 1), first: DateTime(1920), last: today(), help: 'Birthday');
                if (d != null) setState(() => _birthday = d);
              },
            ),
          ],
        ),
        if (_isNew) ...[
          const SizedBox(height: Gap.md),
          BCard(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.sm, Gap.xs),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _paidNow,
              onChanged: (v) => setState(() => _paidNow = v),
              title: Text('First fee paid', style: BasaltType.bodyStrong.copyWith(color: p.text)),
              subtitle: Text(
                _paidNow
                    ? 'Records the fee as paid from the joining date.'
                    : 'The fee will show as due from the joining date.',
                style: BasaltType.caption.copyWith(color: p.textMuted),
              ),
            ),
          ),
        ],
        const SizedBox(height: Gap.md),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Notes', hintText: 'Goals, health notes, trainer…', alignLabelWithHint: true),
        ),
      ],
    );
  }
}
