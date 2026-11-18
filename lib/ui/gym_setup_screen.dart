import 'package:basalt/basalt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import 'backup_screen.dart';
import 'common.dart';

/// One-time setup after the introduction.
class GymSetupScreen extends StatefulWidget {
  const GymSetupScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<GymSetupScreen> createState() => _GymSetupScreenState();
}

class _GymSetupScreenState extends State<GymSetupScreen> {
  final _name = TextEditingController();
  final _currency = TextEditingController(text: 'Rs');
  final _fee = TextEditingController();
  bool _busy = false;
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    _currency.dispose();
    _fee.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Enter your gym name');
      return;
    }
    final fee = parseAmount(_fee.text);
    if (fee == null || fee < 0) {
      BToast.show(context, 'Enter the monthly fee as a number.');
      return;
    }
    setState(() => _busy = true);
    final ok = await attempt(context, () async {
      await context.app.repo.setupGym(name: _name.text, currency: _currency.text, monthlyFee: fee);
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.basalt;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xxl, Gap.xl, Gap.xl),
          children: [
            const BIconTile(Icons.fitness_center_rounded, size: 56),
            const SizedBox(height: Gap.xl),
            Text('Set up your gym', style: BasaltType.hero.copyWith(color: p.text)),
            const SizedBox(height: Gap.sm),
            Text(
              'This appears on reminders and receipts. You can change it later in Settings.',
              style: BasaltType.body.copyWith(color: p.textMuted),
            ),
            const SizedBox(height: Gap.xl),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: 'Gym name', errorText: _nameError),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _currency,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Currency'),
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: TextField(
                    controller: _fee,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: const InputDecoration(labelText: 'Monthly fee', hintText: 'e.g. 3000'),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Text(
              'Monthly, quarterly, half-yearly and yearly plans are created from this fee. Edit them any time.',
              style: BasaltType.caption.copyWith(color: p.textFaint),
            ),
            const SizedBox(height: Gap.xl),
            BButton(label: 'Continue', onPressed: _save, busy: _busy, expand: true),
            const SizedBox(height: Gap.sm),
            BButton(
              label: 'Restore from a backup',
              variant: BButtonVariant.ghost,
              expand: true,
              onPressed: _busy ? null : () => restoreBackupFlow(context),
            ),
          ],
        ),
      ),
    );
  }
}
