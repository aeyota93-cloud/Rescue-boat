import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_colors.dart';
import 'package:hiddify/features/rescue_ui/widgets/rescue_logo.dart';

/// Пункт навигации [RescueShell].
class RescueNavItem {
  const RescueNavItem({required this.icon, required this.label, this.selectedIcon, this.badge = false, this.count});

  final IconData icon;
  final IconData? selectedIcon;

  /// Подпись пункта (в узком меню — всплывающая подсказка) и текст для экранного чтеца.
  final String label;

  /// Оранжевая точка-уведомление («есть новое»), если нет [count].
  final bool badge;

  /// Оранжевый счётчик справа от подписи (в узком меню — в углу значка), например ошибки за час.
  /// null или 0 — счётчика нет; больше 99 показывается как «99+».
  final int? count;
}

/// Каркас: рейка значков 72 px; на узком окне навигация снизу.
class RescueShell extends StatelessWidget {
  const RescueShell({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.child,
    this.bottomItem,
    this.compactWidth = 600,
    this.iconsOnlyWidth = 900,
    this.footer,
    this.compactFooter,
    this.versionLabel,
    this.title = 'Шлюпка',
    this.subtitle = 'спасения',
    this.contentPadding = const EdgeInsets.all(24),
  });

  final List<RescueNavItem> items;
  final RescueNavItem? bottomItem;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget child;

  /// Уже этой ширины — панель значков внизу.
  final double compactWidth;

  /// Уже этой ширины — меню только значками.
  final double iconsOnlyWidth;

  /// Низ широкого меню: карточка статуса с мини-кнопкой питания ([ShellStatusCard]).
  final Widget? footer;

  /// Низ меню значками (600–900 px): например, одна [PowerButton.mini]. В нижней панели не показывается.
  final Widget? compactFooter;

  /// Строка под [footer]: «Версия 0.3.0 · основано на Hiddify». Только в широком меню.
  final String? versionLabel;

  /// Название рядом с логотипом в две строки.
  final String title;
  final String subtitle;

  /// Отступ внутри области раздела.
  final EdgeInsetsGeometry contentPadding;

  /// Ширина широкого меню и меню значками.
  static const sidebarWidth = 236.0;
  static const railWidth = 72.0;

  /// Размер «ушка» — вогнутого уголка над и под выбранным пунктом.
  static const earSize = 20.0;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RescueColors.page,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          if (w < compactWidth) return _buildBottomBar();
          return _buildSide(full: w >= iconsOnlyWidth);
        },
      ),
    );
  }

  List<(int, RescueNavItem)> get _entries => [...items.indexed, if (bottomItem case final b?) (items.length, b)];

  Widget _buildSide({required bool full}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('rescue-shell-rail'),
          width: railWidth,
          decoration: const BoxDecoration(
            color: RescueColors.panel,
            border: Border(right: BorderSide(color: RescueColors.line)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 11.5, vertical: 24),
          child: Column(
            children: [
              Tooltip(
                message: '$title $subtitle',
                child: Semantics(label: '$title $subtitle', child: const RescueLogo()),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  label: 'Разделы',
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final (index, item) in items.indexed) ...[
                          _SideItem(item: item, selected: index == selectedIndex, onTap: () => onSelected(index)),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (bottomItem case final item?) ...[
                const SizedBox(height: 12),
                _SideItem(item: item, selected: selectedIndex == items.length, onTap: () => onSelected(items.length)),
              ],
              if (full ? footer ?? compactFooter : compactFooter case final status?) ...[
                const SizedBox(height: 16),
                Tooltip(message: versionLabel ?? '$title $subtitle', child: status),
              ],
            ],
          ),
        ),
        Expanded(
          child: Container(
            key: const ValueKey('rescue-shell-area'),
            padding: contentPadding,
            color: RescueColors.page,
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: Container(
              key: const ValueKey('rescue-shell-area'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: RescueColors.panel, borderRadius: BorderRadius.circular(24)),
              child: child,
            ),
          ),
        ),
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Разделы',
          child: ColoredBox(
            key: const ValueKey('rescue-shell-bottom-bar'),
            color: RescueColors.page,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final (index, item) in _entries)
                      _BottomItem(item: item, selected: index == selectedIndex, onTap: () => onSelected(index)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _spokenLabel(RescueNavItem item) {
  final count = item.count ?? 0;
  if (count > 0) return '${item.label}, $count';
  return item.badge ? '${item.label}, есть новое' : item.label;
}

String _countText(int count) => count > 99 ? '99+' : '$count';

/// Счётчик: спокойная серая плашка (line2, текст subOnDeep — контраст 4.7:1). Не оранжевый: в «Ошибки»
/// заходят по нужде, а не по каждому сбросу соединения.
class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count, {this.small = false});

  final int count;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('rescue-shell-count'),
      constraints: BoxConstraints(minWidth: small ? 16 : 22),
      padding: EdgeInsets.symmetric(horizontal: small ? 4 : 7, vertical: small ? 0 : 1),
      decoration: BoxDecoration(color: RescueColors.accentTint, borderRadius: BorderRadius.circular(small ? 8 : 6)),
      child: Text(
        _countText(count),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: small ? 10 : 11, fontWeight: FontWeight.w700, color: RescueColors.accent),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 8,
    child: DecoratedBox(
      decoration: BoxDecoration(color: RescueColors.warn, shape: BoxShape.circle),
    ),
  );
}

/// Квадратная плитка с подсказкой, счётчиком и доступным названием.
class _SideItem extends StatelessWidget {
  const _SideItem({required this.item, required this.selected, required this.onTap});
  final RescueNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = item.count ?? 0;
    const shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)));
    return Semantics(
      button: true,
      selected: selected,
      label: _spokenLabel(item),
      onTap: onTap,
      child: ExcludeSemantics(
        child: Tooltip(
          message: item.label,
          excludeFromSemantics: true,
          preferBelow: false,
          child: Material(
            key: selected ? const ValueKey('rescue-shell-selected') : null,
            color: selected ? RescueColors.accentTint : RescueColors.card,
            shape: shape,
            child: InkWell(
              onTap: onTap,
              customBorder: shape,
              focusColor: RescueColors.accent.withValues(alpha: 0.3),
              hoverColor: RescueColors.raised,
              child: SizedBox.square(
                dimension: 48,
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        selected ? (item.selectedIcon ?? item.icon) : item.icon,
                        size: 22,
                        color: selected ? RescueColors.accent : RescueColors.muted,
                      ),
                      if (count > 0)
                        Positioned(top: -10, right: -12, child: _CountBadge(count, small: true))
                      else if (item.badge)
                        const Positioned(top: -3, right: -3, child: _Dot()),
                    ],
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

class _BottomItem extends StatelessWidget {
  const _BottomItem({required this.item, required this.selected, required this.onTap});

  final RescueNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = item.count ?? 0;
    final radius = BorderRadius.circular(16);
    return Semantics(
      button: true,
      selected: selected,
      label: _spokenLabel(item),
      onTap: onTap,
      child: ExcludeSemantics(
        child: Tooltip(
          message: item.label,
          excludeFromSemantics: true,
          preferBelow: false,
          child: Material(
            color: selected ? RescueColors.accentTint : Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              excludeFromSemantics: true,
              child: SizedBox(
                width: 52,
                height: 52,
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        selected ? (item.selectedIcon ?? item.icon) : item.icon,
                        size: 22,
                        color: selected ? RescueColors.accent : RescueColors.text,
                      ),
                      if (count > 0)
                        Positioned(top: -8, right: -14, child: _CountBadge(count, small: true))
                      else if (item.badge)
                        const Positioned(top: -3, right: -3, child: _Dot()),
                    ],
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
