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

/// Шлюпка: каркас окна стиля «Д» — меню слева и область раздела справа.
///
/// Широкое окно (≥ [iconsOnlyWidth], 900): меню 236 px с подписями — логотип и «Шлюпка / спасения»
/// сверху, пункты 52 px, внизу слот [footer] (карточка статуса) и строка [versionLabel].
/// Область справа — panel, радиус 32, отступ [contentPadding] (24). Между меню и областью нет
/// зазора: **выбранный пункт** цвета panel со скруглением только слева прилегает к области,
/// над и под ним «ушки» 20×20 (вогнутые уголки) — выглядит как закладка, вытянутая в область.
///
/// Средняя ширина (≥ [compactWidth], 600): меню только значками (72 px), принцип слияния тот же;
/// подписи — во всплывающих подсказках, вместо [footer] показывается [compactFooter].
/// Узкое окно (< 600): область сверху, панель значков снизу.
///
/// Индексы: `0..items.length-1` — пункты по порядку, `items.length` — [bottomItem] (Настройки);
/// в меню он идёт последним пунктом списка, как в макете.
///
/// Подключение карточки статуса и счётчика:
/// ```dart
/// RescueShell(
///   items: [..., RescueNavItem(icon: Icons.warning_amber_rounded, label: 'Ошибки', count: errorsLastHour), ...],
///   bottomItem: const RescueNavItem(icon: Icons.tune_rounded, label: 'Настройки'),
///   footer: ShellStatusCard(state: power, title: 'Подключено', subtitle: 'Нидерланды · 48 мс', onPower: toggle),
///   compactFooter: PowerButton.mini(state: power, onPressed: toggle),
///   versionLabel: 'Версия 0.3.0 · основано на Hiddify',
///   selectedIndex: ..., onSelected: ..., child: ...,
/// )
/// ```
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
    final footer = full ? this.footer : compactFooter;
    final version = full ? versionLabel : null;
    return Padding(
      padding: EdgeInsets.all(full ? 20 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            key: const ValueKey('rescue-shell-rail'),
            width: full ? sidebarWidth : railWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8, left: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Brand(full: full, title: title, subtitle: subtitle),
                  Expanded(
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      label: 'Разделы',
                      // Отступ сверху и снизу — место для «ушек» крайних пунктов.
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: earSize),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (i, (index, item)) in _entries.indexed) ...[
                              if (i > 0) const SizedBox(height: 4),
                              _SideItem(
                                item: item,
                                selected: index == selectedIndex,
                                showLabel: full,
                                onTap: () => onSelected(index),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (footer != null)
                    Padding(
                      padding: EdgeInsets.only(right: full ? 0 : 4),
                      child: footer,
                    ),
                  if (version != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                      child: Text(version, style: const TextStyle(fontSize: 11, color: RescueColors.muted)),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              key: const ValueKey('rescue-shell-area'),
              padding: contentPadding,
              decoration: BoxDecoration(color: RescueColors.panel, borderRadius: BorderRadius.circular(32)),
              child: child,
            ),
          ),
        ],
      ),
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

class _Brand extends StatelessWidget {
  const _Brand({required this.full, required this.title, required this.subtitle});

  final bool full;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    if (!full) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, right: 4),
        child: Semantics(
          label: '$title $subtitle',
          child: const Center(child: RescueLogo()),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
      child: Semantics(
        label: '$title $subtitle',
        child: ExcludeSemantics(
          child: Row(
            children: [
              const RescueLogo(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: RescueColors.text),
                    ),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: RescueColors.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _spokenLabel(RescueNavItem item) {
  final count = item.count ?? 0;
  if (count > 0) return '${item.label}, $count';
  return item.badge ? '${item.label}, есть новое' : item.label;
}

String _countText(int count) => count > 99 ? '99+' : '$count';

/// Счётчик: оранжевая плашка с тёмным текстом (контраст 6.3:1).
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
      decoration: BoxDecoration(color: RescueColors.warn, borderRadius: BorderRadius.circular(small ? 8 : 6)),
      child: Text(
        _countText(count),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: small ? 10 : 11, fontWeight: FontWeight.w700, color: RescueColors.onAccent),
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

/// «Ушко» — вогнутый уголок 20×20: снаружи panel, внутри page со скруглением к пункту.
class _Ear extends StatelessWidget {
  const _Ear({required this.top});

  final bool top;

  @override
  Widget build(BuildContext context) {
    const r = Radius.circular(RescueShell.earSize);
    return SizedBox.square(
      key: ValueKey(top ? 'rescue-shell-ear-top' : 'rescue-shell-ear-bottom'),
      dimension: RescueShell.earSize,
      child: ColoredBox(
        color: RescueColors.panel,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: RescueColors.page,
            borderRadius: top ? const BorderRadius.only(bottomRight: r) : const BorderRadius.only(topRight: r),
          ),
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({required this.item, required this.selected, required this.showLabel, required this.onTap});

  final RescueNavItem item;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = item.count ?? 0;
    final shape = RoundedRectangleBorder(
      borderRadius: selected ? const BorderRadius.horizontal(left: Radius.circular(18)) : BorderRadius.circular(16),
    );
    final icon = Icon(selected ? (item.selectedIcon ?? item.icon) : item.icon, size: 20, color: RescueColors.text);

    final Widget content;
    if (showLabel) {
      content = Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: RescueColors.text),
            ),
          ),
          if (count > 0) _CountBadge(count) else if (item.badge) const _Dot(),
        ],
      );
    } else {
      content = Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            icon,
            if (count > 0)
              Positioned(top: -8, right: -14, child: _CountBadge(count, small: true))
            else if (item.badge)
              const Positioned(top: -3, right: -3, child: _Dot()),
          ],
        ),
      );
    }

    Widget tile = Material(
      key: selected ? const ValueKey('rescue-shell-selected') : null,
      color: selected ? RescueColors.panel : Colors.transparent,
      shape: shape,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: showLabel ? 14 : 8),
            child: content,
          ),
        ),
      ),
    );
    if (!showLabel) {
      tile = Tooltip(message: item.label, excludeFromSemantics: true, preferBelow: false, child: tile);
    }

    return Semantics(
      button: true,
      selected: selected,
      label: _spokenLabel(item),
      onTap: onTap,
      child: ExcludeSemantics(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            tile,
            if (selected) ...const [
              Positioned(right: 0, top: -RescueShell.earSize, child: _Ear(top: true)),
              Positioned(right: 0, bottom: -RescueShell.earSize, child: _Ear(top: false)),
            ],
          ],
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
            color: selected ? RescueColors.panel : Colors.transparent,
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
