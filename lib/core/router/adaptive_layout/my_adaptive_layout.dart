import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: каркас нового дизайна — узкая панель слева (на узком окне — снизу) и экран справа.
/// Порядок пунктов совпадает с ветками в routing_config_notifier.dart: Обзор, Раздельный
/// туннель, Ошибки, Подписки и серверы; Настройки — нижний пункт (индекс = items.length).
class MyAdaptiveLayout extends HookConsumerWidget {
  const MyAdaptiveLayout({super.key, required this.navigationShell});

  // managed by go router(Shell Route)
  final StatefulNavigationShell navigationShell;

  static const _items = [
    RescueNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Обзор'),
    RescueNavItem(icon: Icons.call_split_rounded, label: 'Раздельный туннель'),
    RescueNavItem(icon: Icons.warning_amber_rounded, label: 'Ошибки соединений'),
    RescueNavItem(icon: Icons.dns_outlined, selectedIcon: Icons.dns_rounded, label: 'Подписки и серверы'),
  ];
  static const _settings = RescueNavItem(icon: Icons.tune_rounded, label: 'Настройки');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Красная точка у «Ошибок», если за последний час они были.
    final errorsLastHour = ref.watch(errorCountProvider(const Duration(hours: 1)));
    final items = [
      for (final (i, item) in _items.indexed)
        i == 2 && errorsLastHour > 0
            ? RescueNavItem(icon: item.icon, selectedIcon: item.selectedIcon, label: item.label, badge: true)
            : item,
    ];
    return Material(
      color: RescueColors.background,
      child: RescueShell(
        items: items,
        bottomItem: _settings,
        selectedIndex: navigationShell.currentIndex,
        onSelected: (index) => navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex),
        child: navigationShell,
      ),
    );
  }
}
