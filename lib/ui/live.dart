import 'dart:async';

import 'package:basalt/basalt.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/gym_repository.dart';

/// Loads data with [load] and rebuilds whenever the database changes, the app returns to the
/// foreground (the date may have changed) or [deps] change.
class Live<T> extends StatefulWidget {
  const Live({super.key, required this.load, required this.builder, this.deps});

  final Future<T> Function(GymRepository repo) load;
  final Widget Function(BuildContext context, T data) builder;
  final Object? deps;

  @override
  State<Live<T>> createState() => _LiveState<T>();
}

class _LiveState<T> extends State<Live<T>> with WidgetsBindingObserver {
  T? _data;
  bool _has = false;
  Object? _error;
  StreamSubscription<void>? _sub;
  GymRepository? _repo;
  bool _loading = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo == null) {
      _repo = context.app.repo;
      _sub = _repo!.changes.listen((_) => _reload());
      _reload();
    }
  }

  @override
  void didUpdateWidget(covariant Live<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deps != widget.deps) _reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_loading) {
      _dirty = true;
      return;
    }
    _loading = true;
    try {
      do {
        _dirty = false;
        try {
          final data = await widget.load(_repo!);
          if (!mounted) return;
          setState(() {
            _data = data;
            _has = true;
            _error = null;
          });
        } catch (e) {
          if (!mounted) return;
          setState(() => _error = e);
        }
      } while (_dirty && mounted);
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_has) return widget.builder(context, _data as T);
    if (_error != null) {
      return Center(
        child: BEmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load this screen',
          message: _error is AppError ? (_error as AppError).message : '$_error',
          actionLabel: 'Try again',
          onAction: _reload,
        ),
      );
    }
    return const Center(child: Padding(padding: EdgeInsets.all(Gap.xxl), child: CircularProgressIndicator()));
  }
}
