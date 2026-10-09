import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/widgets/rescue_logo.dart';

/// Пункт навигации [RescueShell].
class RescueNavItem {
  const RescueNavItem({required this.icon, required this.label, this.selectedIcon, this.badge = false});

  final IconData icon;
  final IconData? selectedIcon;

  /// Подпись: всплывающая подсказка и текст для экранного чтеца.
  final String label;

  /// Красная точка в углу значка (например, «есть новые ошибки»).
  final bool badge;
}

/// Шлюпка: каркас окна — узкая панель значков 64 px слева и контент справа.
///
/// Индексы: `0..items.length-1` — верхние пункты, `items.length` — [bottomItem] (Настройки).
/// На ширине меньше [compactWidth] панель уезжает вниз.
class RescueShell extends StatelessWidget {
  const RescueShell({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.child,
    this.bottomItem,
    this.compactWidth = 700,
  });

  final List<RescueNavItem> items;
  final RescueNavItem? bottomItem;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget child;
  final double compactWidth;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RescueColors.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < compactWidth;
          return compact ? _buildCompact() : _buildWide();
        },
      ),
    );
  }

  List<Widget> _buttons(Iterable<(int, RescueNavItem)> entries) => [
    for (final (index, item) in entries)
      _NavButton(item: item, selected: index == selectedIndex, onTap: () => onSelected(index)),
  ];

  Iterable<(int, RescueNavItem)> get _top => items.indexed;

  Widget _buildWide() {
    final bottom = bottomItem;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Разделы',
            child: Container(
              key: const ValueKey('rescue-shell-rail'),
              width: 64,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: RescueColors.card,
                border: Border.all(color: RescueColors.line),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Padding(padding: EdgeInsets.only(bottom: 12), child: RescueLogo()),
                  // Если окно низкое, пункты прокручиваются, а не вылезают.
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final b in _buttons(_top)) Padding(padding: const EdgeInsets.only(bottom: 6), child: b),
                        ],
                      ),
                    ),
                  ),
                  if (bottom != null) ..._buttons([(items.length, bottom)]),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildCompact() {
    final bottom = bottomItem;
    return Column(
      children: [
        Expanded(
          child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: child),
        ),
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Разделы',
          child: Container(
            key: const ValueKey('rescue-shell-bottom-bar'),
            decoration: const BoxDecoration(
              color: RescueColors.card,
              border: Border(top: BorderSide(color: RescueColors.line)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _buttons([..._top, if (bottom != null) (items.length, bottom)]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final RescueNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Semantics(
      button: true,
      selected: selected,
      label: item.badge ? '${item.label}, есть новое' : item.label,
      onTap: onTap,
      child: Tooltip(
        message: item.label,
        excludeFromSemantics: true,
        preferBelow: false,
        child: Material(
          color: selected ? RescueColors.softAccent : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            excludeFromSemantics: true,
            child: SizedBox.square(
              dimension: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    selected ? (item.selectedIcon ?? item.icon) : item.icon,
                    size: 20,
                    color: selected ? RescueColors.softAccentText : RescueColors.textSecondary,
                  ),
                  if (item.badge)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: SizedBox.square(
                        dimension: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: RescueColors.poor, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
