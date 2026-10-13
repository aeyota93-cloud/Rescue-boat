import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/servers/model/rescue_servers.dart';
import 'package:hiddify/features/servers/model/servers_format.dart';
import 'package:hiddify/features/servers/notifier/failover.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: пункты меню «куда направить» для одной записи (docs/redesign/servers-v2.md):
/// «Через VPN ▸ Авто / Основной / Запасной 1 / …» с галочкой у текущего, «Мимо VPN»,
/// «Сравнить пути…», «Убрать из списков». Если в профиле один сервер — подменю нет.
List<Widget> routeMenuItems({
  required WidgetRef ref,
  required SplitTunnel split,
  required RescueServers? servers,
  required SplitKind kind,
  required String value,
  VoidCallback? onCompare,
}) {
  final notifier = ref.read(splitTunnelProvider.notifier);
  final target = split.targetOf(kind, value);
  final server = split.serverOf(kind, value);
  final via = target == SplitTarget.via;
  final several = servers != null && servers.several;
  // Закреплён за сервером, которого нет в подписке: показываем, чтобы было видно, где он сейчас.
  final lost = server != null && servers != null && servers.byTag(server) == null;

  return [
    if (several)
      SubmenuButton(
        key: ValueKey('route-via-$value'),
        leadingIcon: _Check(via),
        menuChildren: [
          MenuItemButton(
            leadingIcon: _Check(via && server == null),
            onPressed: () => notifier.add(SplitTarget.via, kind, value),
            child: const Text('Авто (основной, при сбое — запасные)'),
          ),
          for (final s in servers.servers)
            MenuItemButton(
              leadingIcon: _Check(server == s.tag),
              onPressed: () => notifier.addToServer(s.tag, kind, value),
              child: _ServerItem(server: s),
            ),
          if (lost)
            MenuItemButton(
              leadingIcon: const _Check(true),
              child: Text('«${serverTitle(server)}» — сервера нет, идёт через Авто'),
            ),
        ],
        child: const Text('Через VPN'),
      )
    else
      MenuItemButton(
        leadingIcon: _Check(via),
        onPressed: () => notifier.add(SplitTarget.via, kind, value),
        child: const Text('Через VPN'),
      ),
    MenuItemButton(
      leadingIcon: _Check(target == SplitTarget.bypass),
      onPressed: () => notifier.add(SplitTarget.bypass, kind, value),
      child: const Text('Мимо VPN'),
    ),
    if (onCompare != null)
      MenuItemButton(leadingIcon: const _Check(false), onPressed: onCompare, child: const Text('Сравнить пути…')),
    MenuItemButton(
      leadingIcon: const _Check(false),
      onPressed: target == null ? null : () => notifier.removeEverywhere(kind, [value]),
      child: const Text('Убрать из списков'),
    ),
  ];
}

/// Кнопка «⋯» строки с меню [routeMenuItems].
class RouteMenuButton extends ConsumerWidget {
  const RouteMenuButton({
    super.key,
    required this.kind,
    required this.value,
    required this.label,
    this.onCompare,
    this.color,
  });

  final SplitKind kind;
  final String value;

  /// Как запись названа в строке — для подсказки и чтеца.
  final String label;
  final VoidCallback? onCompare;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitTunnelProvider);
    final servers = ref.watch(rescueServersProvider);
    return MenuAnchor(
      menuChildren: routeMenuItems(
        ref: ref,
        split: split,
        servers: servers,
        kind: kind,
        value: value,
        onCompare: onCompare,
      ),
      builder: (context, controller, _) => IconButton(
        tooltip: 'Куда направить: $label',
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        style: IconButton.styleFrom(minimumSize: const Size(44, 44), foregroundColor: color),
        icon: const Icon(Icons.more_vert_rounded, size: 22),
      ),
    );
  }
}

/// Галочка у текущего места; у остальных — пустое место той же ширины, чтобы текст стоял ровно.
class _Check extends StatelessWidget {
  const _Check(this.on);

  final bool on;

  @override
  Widget build(BuildContext context) => on
      ? const Icon(Icons.check_rounded, size: 18, color: RescueColors.accent, semanticLabel: 'выбрано')
      : const SizedBox(width: 18);
}

/// «Запасной 2» и мелко — подсказка и имя из подписки.
class _ServerItem extends StatelessWidget {
  const _ServerItem({required this.server});

  final RescueServer server;

  @override
  Widget build(BuildContext context) {
    final hint = server.hint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(server.name),
        Text([?hint, server.title].join(' · '), style: const TextStyle(fontSize: 12, color: RescueColors.muted)),
      ],
    );
  }
}
