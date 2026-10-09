import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Один сегмент [RescueSegmented].
class RescueSegment<T> {
  const RescueSegment({
    required this.value,
    required this.label,
    this.semanticLabel,
    this.selectedBackground = RescueColors.softAccent,
    this.selectedForeground = RescueColors.softAccentText,
  });

  final T value;
  final String label;

  /// Полная подпись для экранного чтеца («Мимо» → «Мимо VPN»).
  final String? semanticLabel;
  final Color selectedBackground;
  final Color selectedForeground;
}

/// Шлюпка: сегментированный переключатель «одно из нескольких» — основа RouteSwitch и PeriodSwitch.
///
/// Клавиатура: одна остановка Tab, стрелки ←/→ (и ↑/↓) выбирают соседний сегмент, Home/End — крайние.
/// Зона нажатия сегмента — вся высота вместе с внутренним отступом (не меньше 44 px).
class RescueSegmented<T> extends StatefulWidget {
  const RescueSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.expand = false,
    this.background = RescueColors.card,
    this.outerRadius = 12,
    this.innerRadius = 9,
    this.segmentHeight = 38,
    this.fontSize = 13,
    this.segmentPadding = 14,
  });

  final List<RescueSegment<T>> segments;
  final T value;

  /// null — переключатель неактивен.
  final ValueChanged<T>? onChanged;

  /// Название группы для экранного чтеца («Период», «Куда идёт Google Chrome»).
  final String? semanticLabel;

  /// Сегменты одинаковой ширины на всю доступную ширину.
  final bool expand;
  final Color background;
  final double outerRadius;
  final double innerRadius;
  final double segmentHeight;
  final double fontSize;
  final double segmentPadding;

  @override
  State<RescueSegmented<T>> createState() => _RescueSegmentedState<T>();
}

class _RescueSegmentedState<T> extends State<RescueSegmented<T>> {
  static const _inset = 3.0;
  bool _focused = false;

  int get _index => widget.segments.indexWhere((s) => s.value == widget.value);

  void _select(int index) {
    final onChanged = widget.onChanged;
    if (onChanged == null || widget.segments.isEmpty) return;
    final i = index.clamp(0, widget.segments.length - 1);
    final value = widget.segments[i].value;
    if (value != widget.value) onChanged(value);
  }

  void _step(int delta) {
    final n = widget.segments.length;
    if (n == 0) return;
    final current = _index < 0 ? 0 : _index;
    _select((current + delta + n) % n);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final segments = widget.segments;
    final children = <Widget>[
      for (final (i, s) in segments.indexed) _buildSegment(i, s, first: i == 0, last: i == segments.length - 1),
    ];

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowLeft): _StepIntent(-1),
          SingleActivator(LogicalKeyboardKey.arrowUp): _StepIntent(-1),
          SingleActivator(LogicalKeyboardKey.arrowRight): _StepIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowDown): _StepIntent(1),
          SingleActivator(LogicalKeyboardKey.home): _JumpIntent(first: true),
          SingleActivator(LogicalKeyboardKey.end): _JumpIntent(first: false),
        },
        actions: {
          _StepIntent: CallbackAction<_StepIntent>(onInvoke: (i) => _step(i.delta)),
          _JumpIntent: CallbackAction<_JumpIntent>(onInvoke: (i) => _select(i.first ? 0 : segments.length - 1)),
        },
        child: Container(
          decoration: BoxDecoration(
            color: widget.background,
            border: Border.all(color: _focused ? RescueColors.accent : RescueColors.line),
            borderRadius: BorderRadius.circular(widget.outerRadius),
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            children: widget.expand ? [for (final c in children) Expanded(child: c)] : children,
          ),
        ),
      ),
    );
  }

  Widget _buildSegment(int index, RescueSegment<T> s, {required bool first, required bool last}) {
    final selected = s.value == widget.value;
    final enabled = widget.onChanged != null;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      selected: selected,
      button: true,
      enabled: enabled,
      label: s.semanticLabel ?? s.label,
      onTap: enabled ? () => _select(index) : null,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => _select(index) : null,
            child: Padding(
              padding: EdgeInsets.fromLTRB(first ? _inset : 0, _inset, last ? _inset : 0, _inset),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: widget.segmentHeight,
                padding: EdgeInsets.symmetric(horizontal: widget.expand ? 4 : widget.segmentPadding),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? s.selectedBackground : Colors.transparent,
                  borderRadius: BorderRadius.circular(widget.innerRadius),
                ),
                child: Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: widget.fontSize,
                    fontWeight: FontWeight.w600,
                    color: selected ? s.selectedForeground : RescueColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepIntent extends Intent {
  const _StepIntent(this.delta);
  final int delta;
}

class _JumpIntent extends Intent {
  const _JumpIntent({required this.first});
  final bool first;
}
