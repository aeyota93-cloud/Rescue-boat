import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/rescue_text.dart';
import 'package:hiddify/features/rescue_ui/widgets/section_label.dart';

/// Одна закладка [FolderTabs].
class FolderTab<T> {
  const FolderTab({required this.value, required this.title, this.badge, this.semanticLabel});

  final T value;

  /// Название закладки: 24 / 300 («Связь», «Здоровье», «Все»).
  final String title;

  /// Метка-рамка справа от названия: число или «ВКЛ».
  final String? badge;

  /// Как прочитать закладку чтецу; null — «название, метка».
  final String? semanticLabel;
}

/// Шлюпка: закладки-«папки» над карточкой (приём 2 стиля «Д»).
///
/// Активная закладка того же цвета, что карточка под ней, и сливается с ней; у карточки нет
/// верхнего левого скругления, когда активна первая закладка. Неактивные — прозрачные.
///
/// ```dart
/// FolderTabs<String>(
///   tabs: const [FolderTab(value: 'now', title: 'Связь', badge: 'ВКЛ'), FolderTab(value: 'health', title: 'Здоровье', badge: '92')],
///   value: tab,
///   onChanged: (t) => setState(() => tab = t),
///   inactiveForeground: RescueColors.onAccent, // закладки стоят на жёлтом
///   child: ...,
/// )
/// ```
/// Клавиатура: одна остановка Tab на ряд закладок, ←/→ — соседняя, Home/End — крайние.
class FolderTabs<T> extends StatefulWidget {
  const FolderTabs({
    super.key,
    required this.tabs,
    required this.value,
    required this.onChanged,
    required this.child,
    this.cardColor = RescueColors.card,
    this.activeForeground = RescueColors.text,
    this.inactiveForeground = RescueColors.text,
    this.padding = const EdgeInsets.all(20),
    this.radius = 28,
    this.semanticLabel,
  });

  final List<FolderTab<T>> tabs;
  final T value;

  /// null — закладки не переключаются.
  final ValueChanged<T>? onChanged;

  /// Содержимое карточки под закладками.
  final Widget child;

  /// Цвет карточки и активной закладки.
  final Color cardColor;

  /// Цвет названия активной и неактивных закладок. На жёлтом фоне неактивные — [RescueColors.onAccent].
  final Color activeForeground;
  final Color inactiveForeground;
  final EdgeInsetsGeometry padding;

  /// Радиус карточки (у закладок верхние углы 22).
  final double radius;

  /// Название ряда закладок для чтеца («Сводка», «Списки»).
  final String? semanticLabel;

  @override
  State<FolderTabs<T>> createState() => _FolderTabsState<T>();
}

class _FolderTabsState<T> extends State<FolderTabs<T>> {
  bool _focused = false;

  int get _index => widget.tabs.indexWhere((t) => t.value == widget.value);

  void _select(int i) {
    final onChanged = widget.onChanged;
    if (onChanged == null || widget.tabs.isEmpty) return;
    final value = widget.tabs[i.clamp(0, widget.tabs.length - 1)].value;
    if (value != widget.value) onChanged(value);
  }

  void _step(int delta) {
    final n = widget.tabs.length;
    if (n == 0) return;
    _select(((_index < 0 ? 0 : _index) + delta + n) % n);
  }

  @override
  Widget build(BuildContext context) {
    final r = Radius.circular(widget.radius);
    final firstActive = _index == 0;
    final enabled = widget.onChanged != null;
    final tabs = Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowLeft): _StepIntent(-1),
          SingleActivator(LogicalKeyboardKey.arrowRight): _StepIntent(1),
          SingleActivator(LogicalKeyboardKey.home): _JumpIntent(first: true),
          SingleActivator(LogicalKeyboardKey.end): _JumpIntent(first: false),
        },
        actions: {
          _StepIntent: CallbackAction<_StepIntent>(onInvoke: (i) => _step(i.delta)),
          _JumpIntent: CallbackAction<_JumpIntent>(onInvoke: (i) => _select(i.first ? 0 : widget.tabs.length - 1)),
        },
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, t) in widget.tabs.indexed) ...[if (i > 0) const SizedBox(width: 2), _buildTab(i, t)],
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        tabs,
        Container(
          key: const ValueKey('folder-tabs-card'),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.cardColor,
            borderRadius: BorderRadius.only(
              topLeft: firstActive ? Radius.zero : r,
              topRight: r,
              bottomLeft: r,
              bottomRight: r,
            ),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: widget.activeForeground),
            child: widget.child,
          ),
        ),
      ],
    );
  }

  Widget _buildTab(int index, FolderTab<T> t) {
    final selected = index == _index;
    final enabled = widget.onChanged != null;
    final fg = selected ? widget.activeForeground : widget.inactiveForeground;
    final badge = t.badge;
    return Semantics(
      key: ValueKey('folder-tab-$index'),
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      enabled: enabled,
      label: t.semanticLabel ?? [t.title, ?badge].join(', '),
      onTap: enabled ? () => _select(index) : null,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => _select(index) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              decoration: BoxDecoration(
                color: selected ? widget.cardColor : Colors.transparent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              ),
              foregroundDecoration: selected && _focused
                  ? BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                      border: Border.all(color: RescueColors.accent, width: 1.5),
                    )
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.title, style: RescueText.tabTitle.copyWith(color: fg)),
                  if (badge != null) ...[const SizedBox(width: 8), FrameTag(badge, color: fg)],
                ],
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
