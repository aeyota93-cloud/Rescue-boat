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
///
/// [values] — несколько записей сразу (группа «Игры и лаунчеры»): выбор ставит все в одно место,
/// галочка — только если там все. «Убрать из списков» у группы нет: у игр по умолчанию это «мимо».
List<Widget> routeMenuItems({
  required WidgetRef ref,
  required SplitTunnel split,
  required RescueServers? servers,
  required SplitKind kind,
  required List<String> values,
  VoidCallback? onCompare,
}) {
  final notifier = ref.read(splitTunnelProvider.notifier);
  final single = values.length == 1;
  final targets = {for (final v in values) split.targetOf(kind, v)};
  final places = {for (final v in values) split.serverOf(kind, v)};
  final target = targets.length == 1 ? targets.single : null;
  // Сервер, общий для всех; null — «Авто» у всех или места разные.
  final server = places.length == 1 ? places.single : null;
  final via = target == SplitTarget.via;
  final several = servers != null && servers.several;
  // Закреплён за сервером, которого нет в подписке: показываем, чтобы было видно, где он сейчас.
  final lost = server != null && servers != null && servers.byTag(server) == null;

  void toVia() => notifier.addAll(SplitTarget.via, kind, values);

  return [
    if (several)
      SubmenuButton(
        key: ValueKey('route-via-${values.first}${single ? '' : '+${values.length - 1}'}'),
        leadingIcon: _Check(via),
        menuChildren: [
          MenuItemButton(
            leadingIcon: _Check(via && server == null && places.length == 1),
            onPressed: toVia,
            child: const Text('Авто (основной, при сбое — запасные)'),
          ),
          for (final s in servers.servers)
            MenuItemButton(
              leadingIcon: _Check(server == s.tag),
              onPressed: () => notifier.addAllToServer(s.tag, kind, values),
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
      MenuItemButton(leadingIcon: _Check(via), onPressed: toVia, child: const Text('Через VPN')),
    MenuItemButton(
      leadingIcon: _Check(target == SplitTarget.bypass),
      onPressed: () => notifier.addAll(SplitTarget.bypass, kind, values),
      child: const Text('Мимо VPN'),
    ),
    if (onCompare != null)
      MenuItemButton(leadingIcon: const _Check(false), onPressed: onCompare, child: const Text('Сравнить пути…')),
    if (single)
      MenuItemButton(
        leadingIcon: const _Check(false),
        onPressed: target == null ? null : () => notifier.removeEverywhere(kind, values),
        child: const Text('Убрать из списков'),
      ),
  ];
}

/// Кнопка «⋯» строки с меню [routeMenuItems]. [values] — для группы записей, иначе [value].
class RouteMenuButton extends ConsumerWidget {
  const RouteMenuButton({
    super.key,
    required this.kind,
    required this.value,
    required this.label,
    this.values,
    this.onCompare,
    this.color,
  });

  final SplitKind kind;
  final String value;
  final List<String>? values;

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
        values: values ?? [value],
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
