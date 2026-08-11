import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'responsive.dart';

/// Пульс-подсветка якоря за полупрозрачным диалогом (пилот: касса, сотрудники).
///
/// Desktop only + без reduce-motion. На mobile не включаем — фон почти не виден.
bool pulseAnchorsEnabled(BuildContext context) {
  if (!AppResponsive.isWide(context)) return false;
  return !MediaQuery.disableAnimationsOf(context);
}

/// Mixin: один активный id на экран, пока открыта форма.
mixin PulseHighlightMixin<T extends StatefulWidget> on State<T> {
  Object? pulseHighlightId;

  bool isPulseActive(Object id) => pulseHighlightId == id;

  Future<R?> runWithPulseHighlight<R>(
    Object id,
    Future<R?> Function() action,
  ) async {
    final enable = pulseAnchorsEnabled(context);
    if (enable) setState(() => pulseHighlightId = id);
    try {
      return await action();
    } finally {
      if (mounted && pulseHighlightId == id) {
        setState(() => pulseHighlightId = null);
      }
    }
  }
}

/// Оборачивает виджет: при [active] мягко пульсирует, затем держит тихое свечение.
class PulseAnchor extends StatefulWidget {
  final bool active;
  final Widget child;
  final Color accent;
  final BorderRadius borderRadius;

  const PulseAnchor({
    super.key,
    required this.active,
    required this.child,
    this.accent = AppColors.primary,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppTheme.radiusLg)),
  });

  @override
  State<PulseAnchor> createState() => _PulseAnchorState();
}

class _PulseAnchorState extends State<PulseAnchor> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _runToken = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.active) _startPulse();
  }

  @override
  void didUpdateWidget(covariant PulseAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _startPulse();
    } else if (!widget.active && oldWidget.active) {
      _stopPulse();
    }
  }

  Future<void> _startPulse() async {
    final token = ++_runToken;
    _ctrl.stop();
    _ctrl.value = 0;
    // 3 цикла, потом статичная мягкая подсветка.
    for (var i = 0; i < 3; i++) {
      if (!mounted || token != _runToken || !widget.active) return;
      await _ctrl.forward();
      if (!mounted || token != _runToken || !widget.active) return;
      await _ctrl.reverse();
    }
    if (!mounted || token != _runToken || !widget.active) return;
    await _ctrl.animateTo(0.45, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  void _stopPulse() {
    _runToken++;
    if (!_ctrl.isAnimating && _ctrl.value == 0) return;
    _ctrl.stop();
    _ctrl.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _runToken++;
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        final glow = widget.active || t > 0.01;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: glow
                ? [
                    BoxShadow(
                      color: widget.accent.withOpacity(0.12 + 0.38 * t),
                      blurRadius: 6 + 14 * t,
                      spreadRadius: 0.5 + 2.5 * t,
                    ),
                  ]
                : null,
            border: glow
                ? Border.all(
                    color: widget.accent.withOpacity(0.2 + 0.55 * t),
                    width: 1.25 + 0.75 * t,
                  )
                : null,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
