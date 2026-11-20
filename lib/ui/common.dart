import 'package:basalt/basalt.dart';
import 'package:flutter/material.dart';

import '../data/gym_repository.dart';
import '../domain/member_view.dart';

/// Runs [action] and shows a toast if it throws. Returns null on failure.
Future<T?> attempt<T>(BuildContext context, Future<T> Function() action) async {
  try {
    return await action();
  } catch (e) {
    if (context.mounted) BToast.show(context, errorText(e));
    return null;
  }
}

String errorText(Object e) => e is AppError ? e.message : 'Something went wrong: $e';

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 40, this.color});

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.basalt;
    final c = color ?? p.accent;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.soft(c), shape: BoxShape.circle),
      child: Text(
        initials(name),
        style: BasaltType.label.copyWith(color: c, fontWeight: FontWeight.w600, fontSize: size * 0.36),
      ),
    );
  }
}

Color statusColor(BuildContext context, MemberView m) {
  final p = context.basalt;
  if (m.isInactive) return p.textFaint;
  if (m.isFrozen) return p.textMuted;
  if (m.isOverdue) return p.danger;
  if (m.isDueSoon) return p.warning;
  return p.success;
}

/// Consistent bottom sheet: drag handle, title, scrollable body that stays above the keyboard.
Future<T?> showSheet<T>(BuildContext context, {required String title, required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      final p = ctx.basalt;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: BasaltType.title.copyWith(color: p.text)),
              const SizedBox(height: Gap.lg),
              builder(ctx),
            ],
          ),
        ),
      );
    },
  );
}

/// A label/value line inside cards.
class InfoLine extends StatelessWidget {
  const InfoLine(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final p = context.basalt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: BasaltType.body.copyWith(color: p.textMuted, fontSize: 14)),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: BasaltType.bodyStrong.copyWith(color: valueColor ?? p.text, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple page with a standard app bar, for pushed screens.
class SubPage extends StatelessWidget {
  const SubPage({super.key, required this.title, required this.children, this.actions = const [], this.bottom});

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: ListView(padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl), children: children),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.md), child: bottom)),
    );
  }
}

double? parseAmount(String s) {
  final t = s.replaceAll(',', '').trim();
  if (t.isEmpty) return 0;
  return double.tryParse(t);
}

String amountText(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
