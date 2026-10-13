import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/servers/model/rescue_servers.dart';
import 'package:hiddify/features/servers/model/servers_format.dart';
import 'package:hiddify/features/servers/notifier/failover.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: пункты меню «куда направить» (docs/redesign/servers-v2.md, docs/redesign/groups.md):
/// «Через VPN ▸ Авто / Основной / Запасной 1 / …» с галочкой у текущего, «Мимо VPN»,
/// «Сравнить пути…», «Убрать из списков», «В группу ▸ …». Если в профиле один сервер — подменю нет.
///
/// [items] — одна запись или все записи группы [group]: выбор ставит все в одно место, галочка —
/// только если там все. У группы вместо «Убрать из списков» и «В группу» — «Переименовать» и
/// «Удалить группу». [withGroups] = false — без пунктов про группы (окно «Сейчас в сети»).
List<Widget> routeMenuItems({
  required BuildContext context,
  required WidgetRef ref,
  required SplitTunnel split,
  required RescueServers? servers,
  required List<SplitRef> items,
  String? group,
  bool withGroups = true,
  VoidCallback? onCompare,
}) {
  final notifier = ref.read(splitTunnelProvider.notifier);
  final first = items.first;
  final targets = {for (final i in items) split.targetOf(i.kind, i.value)};
  final places = {for (final i in items) split.serverOf(i.kind, i.value)};
  final target = targets.length == 1 ? targets.single : null;
  // Сервер, общий для всех; null — «Авто» у всех или места разные.
  final server = places.length == 1 ? places.single : null;
  final via = target == SplitTarget.via;
  final several = servers != null && servers.several;
  // Закреплён за сервером, которого нет в подписке: показываем, чтобы было видно, где он сейчас.
  final lost = server != null && servers != null && servers.byTag(server) == null;
  final inGroup = group == null ? split.groupOf(first.kind, first.value) : null;

  void toVia() => notifier.placeAll(items, SplitTarget.via);

  return [
    if (several)
      SubmenuButton(
        key: ValueKey('route-via-${group == null ? first.value : 'group-$group'}'),
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
              onPressed: () => notifier.placeAll(items, SplitTarget.via, server: s.tag),
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
      onPressed: () => notifier.placeAll(items, SplitTarget.bypass),
      child: const Text('Мимо VPN'),
    ),
    if (onCompare != null)
      MenuItemButton(leadingIcon: const _Check(false), onPressed: onCompare, child: const Text('Сравнить пути…')),
    if (group == null)
      MenuItemButton(
        leadingIcon: const _Check(false),
        onPressed: target == null ? null : () => notifier.removeEverywhere(first.kind, [first.value]),
        child: const Text('Убрать из списков'),
      ),
    if (withGroups && group == null) ...[
      const Divider(height: 8),
      SubmenuButton(
        key: ValueKey('route-group-${first.value}'),
        leadingIcon: _Check(inGroup != null),
        menuChildren: [
          for (final g in split.groups)
            MenuItemButton(
              leadingIcon: _Check(inGroup != null && sameGroupName(g.name, inGroup)),
              onPressed: () => notifier.moveToGroup(g.name, items),
              child: Text(g.name),
            ),
          MenuItemButton(
            leadingIcon: const _Check(false),
            onPressed: () async {
              final name = await showGroupNameDialog(context, title: 'Новая группа');
              if (name != null) notifier.moveToGroup(name, items);
            },
            child: const Text('Новая группа…'),
          ),
        ],
        child: const Text('В группу'),
      ),
      if (inGroup != null)
        MenuItemButton(
          leadingIcon: const _Check(false),
          onPressed: () => notifier.removeFromGroup(items),
          child: Text('Убрать из группы «$inGroup»'),
        ),
    ],
    if (group != null) ...[
      const Divider(height: 8),
      MenuItemButton(
        leadingIcon: const _Check(false),
        onPressed: () async {
          final name = await showGroupNameDialog(context, title: 'Переименовать группу', initial: group);
          if (name != null) notifier.renameGroup(group, name);
        },
        child: const Text('Переименовать…'),
      ),
      MenuItemButton(
        leadingIcon: const _Check(false),
        onPressed: () => notifier.deleteGroup(group),
        child: const Text('Удалить группу (записи останутся)'),
      ),
    ],
  ];
}

/// Окно с именем группы; null — отмена или пустое имя.
Future<String?> showGroupNameDialog(BuildContext context, {required String title, String initial = ''}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _GroupNameDialog(title: title, initial: initial),
    );

class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() {
    final name = _controller.text.trim();
    Navigator.of(context).pop(name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const ValueKey('group-name'),
      controller: _controller,
      autofocus: true,
      maxLength: 40,
      decoration: const InputDecoration(hintText: 'Например, «Работа и дом»'),
      onSubmitted: (_) => _done(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
      FilledButton(onPressed: _done, child: const Text('Готово')),
    ],
  );
}

/// Кнопка «⋯» строки с меню [routeMenuItems]: одна запись или группа [group] с записями [items].
class RouteMenuButton extends ConsumerWidget {
  const RouteMenuButton({super.key, required this.items, required this.label, this.group, this.onCompare, this.color});

  final List<SplitRef> items;
  final String? group;

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
        context: context,
        ref: ref,
        split: split,
        servers: servers,
        items: items,
        group: group,
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
