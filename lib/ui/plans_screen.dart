import 'package:basalt/basalt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../data/db.dart';
import '../domain/member_view.dart';
import 'common.dart';
import 'live.dart';

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Scaffold(
      appBar: AppBar(title: const Text('Membership plans')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add plan'),
      ),
      body: Live<List<Plan>>(
        load: (repo) => repo.plans(),
        builder: (context, plans) => ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 96),
          children: [
            Text(
              'Plans set the default fee and length when you add a member or record a payment. '
              'Changing a plan does not change members who already have it.',
              style: BasaltType.body.copyWith(color: context.basalt.textMuted, fontSize: 14),
            ),
            const SizedBox(height: Gap.lg),
            if (plans.isEmpty)
              const BEmptyState(icon: Icons.sell_outlined, title: 'No plans yet')
            else
              BGroup(
                children: [
                  for (final plan in plans)
                    BListRow(
                      icon: Icons.sell_outlined,
                      title: plan.name,
                      subtitle: '${monthsLabel(plan.months)} · ${app.money(plan.price)}',
                      chevron: true,
                      onTap: () => _edit(context, plan),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, Plan? plan) async {
    final app = context.app;
    final name = TextEditingController(text: plan?.name ?? '');
    final price = TextEditingController(text: plan == null ? '' : amountText(plan.price));
    var months = plan?.months ?? 1;
    final result = await showSheet<String>(
      context,
      title: plan == null ? 'New plan' : 'Edit plan',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: name,
              autofocus: plan == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Plan name', hintText: 'e.g. Monthly'),
            ),
            const SizedBox(height: Gap.md),
            TextField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(labelText: 'Price', prefixText: '${app.gym.value.currency} '),
            ),
            const BSectionTitle('Length'),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                for (final m in {1, 2, 3, 6, 12, months}.toList()..sort())
                  BChip(label: monthsLabel(m), selected: months == m, onTap: () => setState(() => months = m)),
              ],
            ),
            const SizedBox(height: Gap.xl),
            BButton(label: 'Save plan', expand: true, onPressed: () => Navigator.pop(ctx, 'save')),
            if (plan != null) ...[
              const SizedBox(height: Gap.sm),
              BButton(label: 'Delete plan', variant: BButtonVariant.ghost, expand: true, onPressed: () => Navigator.pop(ctx, 'delete')),
            ],
          ],
        ),
      ),
    );
    if (context.mounted && result == 'save') {
      final value = parseAmount(price.text);
      if (value == null) {
        BToast.show(context, 'Enter the price as a number.');
      } else {
        await attempt(context, () => app.repo.savePlan(id: plan?.id, name: name.text, months: months, price: value));
      }
    } else if (context.mounted && result == 'delete' && plan != null) {
      final ok = await bConfirm(
        context,
        title: 'Delete ${plan.name}?',
        message: 'Members on this plan keep their fee and show "Custom".',
        confirmLabel: 'Delete',
        danger: true,
      );
      if (ok) await app.repo.deletePlan(plan.id);
    }
    // The controllers are left to the garbage collector: the sheet may still be animating out.
  }
}
