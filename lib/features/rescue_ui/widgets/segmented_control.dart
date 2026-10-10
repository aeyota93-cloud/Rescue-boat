import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';

/// Один сегмент [RescueSegmented].
class RescueSegment<T> {
  const RescueSegment({
    required this.value,
    required this.label,
    this.semanticLabel,
    this.selectedBackground,
    this.selectedForeground,
  });

  final T value;
  final String label;

  /// Полная подпись для экранного чтеца («Мимо» → «Мимо VPN»).
  final String? semanticLabel;

  /// Цвета выбранного сегмента; null — как у группы ([RescueSegmented.selectedBackground]).
  final Color? selectedBackground;
  final Color? selectedForeground;
}

/// Шлюпка: сегментированный переключатель «одно из нескольких» — основа PillSegmented,
/// RouteSwitch и PeriodSwitch. По умолчанию — таблетка стиля «Д»: дорожка card, выбранный
/// сегмент светлый ([RescueColors.text]) с тёмным текстом.
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
    this.outerRadius = 999,
    this.innerRadius = 999,
    this.segmentHeight = 38,
    this.fontSize = 13,
    this.segmentPadding = 16,
    this.selectedBackground = RescueColors.text,
    this.selectedForeground = RescueColors.onAccent,
    this.foreground = RescueColors.text,
    this.borderColor,
    this.focusColor = RescueColors.accent,
    this.inset = 3,
    this.gap = 2,
    this.letterSpacing,
  });

  final List<RescueSegment<T>> segments;
  final T value;

  /// null — переключатель неактивен.
  final ValueChanged<T>? onChanged;

  /// Название группы для экранного чтеца («Период», «Куда идёт Google Chrome»).
  final String? semanticLabel;

  /// Сегменты одинаковой ширины на всю доступную ширину.
  final bool expand;

  /// Цвет дорожки.
  final Color background;
  final double outerRadius;
  final double innerRadius;
  final double segmentHeight;
  final double fontSize;
  final double segmentPadding;

  /// Цвета выбранного сегмента по умолчанию (сегмент может задать свои).
  final Color selectedBackground;
  final Color selectedForeground;

  /// Текст невыбранных сегментов.
  final Color foreground;

  /// Рамка дорожки; null — без рамки (рамка появляется только при фокусе с клавиатуры).
  final Color? borderColor;
  final Color focusColor;

  /// Отступ сегментов от края дорожки и промежуток между сегментами.
  final double inset;
  final double gap;
  final double? letterSpacing;

  @override
  State<RescueSegmented<T>> createState() => _RescueSegmentedState<T>();
}

class _RescueSegmentedState<T> extends State<RescueSegmented<T>> {
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
    final border = _focused ? widget.focusColor : widget.borderColor;

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
            // Рамка всегда занимает место (прозрачная), чтобы при фокусе ничего не прыгало.
            border: Border.all(color: border ?? Colors.transparent, width: 1.5),
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
    final inset = widget.inset;
    final halfGap = widget.gap / 2;
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
              padding: EdgeInsets.fromLTRB(first ? inset : halfGap, inset, last ? inset : halfGap, inset),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: widget.segmentHeight,
                padding: EdgeInsets.symmetric(horizontal: widget.expand ? 4 : widget.segmentPadding),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? (s.selectedBackground ?? widget.selectedBackground) : Colors.transparent,
                  borderRadius: BorderRadius.circular(widget.innerRadius),
                ),
                child: Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: widget.fontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: widget.letterSpacing,
                    color: selected ? (s.selectedForeground ?? widget.selectedForeground) : widget.foreground,
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
