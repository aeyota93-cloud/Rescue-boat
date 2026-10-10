import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/overview/notifier/vpn_status.dart';
import 'package:hiddify/features/overview/widget/vpn_power.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: каркас нового дизайна — меню слева (на узком окне — значки снизу) и раздел справа.
class MyAdaptiveLayout extends HookConsumerWidget {
  const MyAdaptiveLayout({super.key, required this.navigationShell});

  // managed by go router(Shell Route)
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RescueAppShell(
      selectedIndex: navigationShell.currentIndex,
      onSelected: (index) => navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex),
      child: navigationShell,
    );
  }
}

/// Каркас с данными приложения: пункты меню, счётчик ошибок за час, карточка статуса VPN
/// с мини-кнопкой питания и строка версии.
///
/// Порядок пунктов совпадает с ветками в routing_config_notifier.dart: Главная, Раздельный
/// туннель, Ошибки, Подписки и серверы; Настройки — последний пункт (индекс = items.length).
class RescueAppShell extends ConsumerWidget {
  const RescueAppShell({super.key, required this.selectedIndex, required this.onSelected, required this.child});

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget child;

  static const errorsIndex = 2;

  static const items = [
    RescueNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Главная'),
    RescueNavItem(icon: Icons.call_split_rounded, label: 'Раздельный туннель'),
    RescueNavItem(icon: Icons.warning_amber_rounded, label: 'Ошибки'),
    RescueNavItem(icon: Icons.dns_outlined, selectedIcon: Icons.dns_rounded, label: 'Подписки и серверы'),
  ];
  static const settings = RescueNavItem(icon: Icons.tune_rounded, label: 'Настройки');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Оранжевый счётчик у «Ошибок»: сколько было за последний час (0 — без счётчика).
    final errorsLastHour = ref.watch(errorCountProvider(const Duration(hours: 1)));
    final vpn = ref.watch(vpnStatusProvider);
    // Время подключения считается, пока жив каркас, — даже если Главная не открыта.
    ref.watch(vpnConnectedSinceProvider);
    final version = ref.watch(appInfoProvider.select((info) => info.valueOrNull?.presentVersion));

    final navItems = [
      for (final (i, item) in items.indexed)
        i == errorsIndex
            ? RescueNavItem(
                icon: item.icon,
                selectedIcon: item.selectedIcon,
                label: item.label,
                count: errorsLastHour > 0 ? errorsLastHour : null,
              )
            : item,
    ];
    final power = vpn.powerLabel;
    void toggle() => toggleVpn(context, ref);

    return Material(
      color: RescueColors.page,
      child: RescueShell(
        items: navItems,
        bottomItem: settings,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
        // Кнопка в карточке видна всегда (без «прыжка» вёрстки), во время переключения нажатие
        // ничего не делает — toggleVpn это проверяет.
        footer: ShellStatusCard(
          state: vpn.power,
          title: vpn.title,
          subtitle: shellStatusSubtitle(vpn),
          onPower: toggle,
          powerLabel: power,
        ),
        compactFooter: Center(
          child: PowerButton.mini(state: vpn.power, onPressed: vpn.canToggle ? toggle : null, semanticLabel: power),
        ),
        versionLabel: version == null ? null : 'Версия $version · основано на Hiddify',
        child: child,
      ),
    );
  }
}

/// Подпись в карточке статуса: «Нидерланды · 48 мс» / «нажмите кнопку».
String? shellStatusSubtitle(VpnStatus vpn) {
  if (vpn.on) {
    final parts = [if (vpn.server.isNotEmpty) vpn.server, if (vpn.delayMs != null) '${vpn.delayMs} мс'];
    return parts.isEmpty ? null : parts.join(' · ');
  }
  if (vpn.busy) return vpn.server.isEmpty ? null : vpn.server;
  return 'нажмите кнопку';
}
