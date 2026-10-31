import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/common/pinned_scroll.dart';
import 'package:hiddify/features/compare/model/compare_target.dart';
import 'package:hiddify/features/compare/widget/compare_paths_dialog.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/servers/model/rescue_servers.dart';
import 'package:hiddify/features/servers/notifier/failover.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/model/app_names.dart';
import 'package:hiddify/features/split_tunnel/model/live_view.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/model/tunnel_rows.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hiddify/features/split_tunnel/widget/place_menu.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Уже 720 px путь располагается под названием программы.
const liveWideFrom = 720.0;

/// Соединения по программам: фактический выход, правило и действия без карточек.
class TunnelLiveView extends HookConsumerWidget {
  const TunnelLiveView({
    super.key,
    required this.connections,
    required this.titles,
    required this.query,
    required this.searchController,
    required this.onQueryChanged,
    required this.pinned,
    required this.onOpenGroup,
    required this.onShowGroups,
  });

  final List<NetConnection>? connections;
  final Map<String, String> titles;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final bool pinned;
  final ValueChanged<String> onOpenGroup;
  final VoidCallback onShowGroups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = useState(LiveFilter.all);
    final searching = useState(query.isNotEmpty);
    final searchFocus = useFocusNode();
    final open = useState(const <String>{});
    final split = ref.watch(splitTunnelProvider);
    final servers = ref.watch(rescueServersProvider);
    final all = connections;
    if (all == null) {
      return _Empty(
        text: 'VPN выключен — соединений не видно. Включите VPN, чтобы видеть, что куда идёт прямо сейчас.',
        action: ('Открыть все правила', onShowGroups),
      );
    }
    String titleOf(String exe) => appTitle(exe, titles);
    final apps = buildLiveApps(split, all, servers, filter: filter.value, query: query, titleOf: titleOf);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= liveWideFrom;
        final rows = <Widget>[];
        for (final app in apps) {
          final key = app.exe.toLowerCase();
          final isOpen = open.value.contains(key);
          rows.add(
            _AppRow(
              key: ValueKey('live-app-${app.exe}'),
              app: app,
              title: titleOf(app.exe),
              wide: wide,
              open: isOpen,
              all: all,
              onToggle: () => open.value = isOpen ? ({...open.value}..remove(key)) : {...open.value, key},
              onOpenGroup: onOpenGroup,
            ),
          );
          if (isOpen) {
            for (final c in app.conns) {
              rows.add(_ConnRow(key: ValueKey('live-conn-${c.connection.id}'), conn: c, wide: wide, servers: servers));
            }
          }
        }
        final tools = Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (value, label) in const [
                      (LiveFilter.all, 'Все'),
                      (LiveFilter.vpn, 'Через VPN'),
                      (LiveFilter.direct, 'Мимо'),
                      (LiveFilter.auto, 'Без правила'),
                    ])
                      Semantics(
                        selected: filter.value == value,
                        inMutuallyExclusiveGroup: true,
                        child: InkWell(
                          onTap: () => filter.value = value,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: filter.value == value ? RescueColors.accent : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                color: filter.value == value ? RescueColors.textOnDeep : RescueColors.subOnDeep,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (searching.value && wide) ...[
              const SizedBox(width: 20),
              SizedBox(
                width: 260,
                child: _LiveSearch(controller: searchController, focusNode: searchFocus, onChanged: onQueryChanged),
              ),
            ],
            IconButton(
              tooltip: searching.value ? 'Закрыть поиск' : 'Поиск соединений',
              onPressed: () {
                searching.value = !searching.value;
                if (searching.value) {
                  searchFocus.requestFocus();
                } else {
                  searchController.clear();
                  onQueryChanged('');
                }
              },
              color: RescueColors.subOnDeep,
              icon: Icon(searching.value ? Icons.close_rounded : Icons.search_rounded, size: 19),
            ),
          ],
        );
        final empty = Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            all.isEmpty
                ? 'Сейчас соединений нет.'
                : (query.isNotEmpty ? 'Ничего не нашлось.' : 'Сейчас ничего не подходит под фильтр.'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: RescueColors.subOnDeep),
          ),
        );
        final list = rows.isEmpty
            ? empty
            : pinned
            ? PinnedList(key: const ValueKey('live-rows'), itemCount: rows.length, itemBuilder: (_, i) => rows[i])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: pinned ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _Summary(connections: all, servers: servers),
            const SizedBox(height: 16),
            tools,
            if (searching.value && !wide)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: _LiveSearch(controller: searchController, focusNode: searchFocus, onChanged: onQueryChanged),
              ),
            const SizedBox(height: 8),
            if (pinned) Expanded(child: list) else list,
          ],
        );
      },
    );
  }
}

class _LiveSearch extends StatelessWidget {
  const _LiveSearch({required this.controller, required this.focusNode, required this.onChanged});
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => TextField(
    key: const ValueKey('live-search'),
    controller: controller,
    focusNode: focusNode,
    autofocus: true,
    onChanged: onChanged,
    style: const TextStyle(fontSize: 13, color: RescueColors.textOnDeep),
    decoration: const InputDecoration(
      hintText: 'Найти программу, сайт или IP',
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: UnderlineInputBorder(borderSide: BorderSide(color: RescueColors.line2)),
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.connections, required this.servers});
  final List<NetConnection> connections;
  final RescueServers? servers;
  @override
  Widget build(BuildContext context) {
    final parts = liveSummary(connections, servers);
    final total = parts.fold(0, (s, p) => s + p.$2);
    final programs = {for (final c in connections.where((c) => !c.closed)) c.exe.toLowerCase()}.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$total ${pluralRu(total, 'соединение', 'соединения', 'соединений')} · '
          '$programs ${pluralRu(programs, 'программа', 'программы', 'программ')} · обновляется каждые 2 секунды',
          style: const TextStyle(fontSize: 12, color: RescueColors.subOnDeep),
        ),
        if (total > 0) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              key: const ValueKey('live-share-bar'),
              height: 4,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (d, n) in parts)
                    Expanded(
                      flex: n,
                      child: ColoredBox(color: destColor(d)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [for (final (d, n) in parts) _DestText(d, label: '${destLabel(d)} · $n')],
          ),
        ],
      ],
    );
  }
}

class _DestText extends StatelessWidget {
  const _DestText(this.dest, {this.label});
  final LiveDest dest;
  final String? label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: destColor(dest), shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          label ?? destLabel(dest),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: RescueColors.subOnDeep),
        ),
      ),
    ],
  );
}

class _AppRow extends ConsumerWidget {
  const _AppRow({
    super.key,
    required this.app,
    required this.title,
    required this.wide,
    required this.open,
    required this.all,
    required this.onToggle,
    required this.onOpenGroup,
  });
  final LiveApp app;
  final String title;
  final bool wide;
  final bool open;
  final List<NetConnection> all;
  final VoidCallback onToggle;
  final ValueChanged<String> onOpenGroup;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final known = app.exe.isNotEmpty;
    final hosts = <String>{for (final c in app.conns) c.address}.toList();
    final sub = [
      if (known) app.exe else 'ядро не узнало программу',
      hosts.take(2).join(', ') + (hosts.length > 2 ? ' +${hosts.length - 2}' : ''),
    ].join(' · ');
    final item = [(kind: SplitKind.app, value: app.exe)];
    final count = '${app.open} ${pluralRu(app.open, 'соединение', 'соединения', 'соединений')}';
    final numbers = Tooltip(
      message: '$count · ${formatBytes(app.bytes)}',
      child: Text(
        wide ? count : '${app.open}',
        overflow: TextOverflow.ellipsis,
        textAlign: wide ? TextAlign.left : TextAlign.right,
        style: const TextStyle(fontSize: 12, color: RescueColors.subOnDeep),
      ),
    );
    final place = ref.watch(splitTunnelProvider).placeOf(SplitKind.app, app.exe);
    final exits = app.dests.map(destLabel).join(', ');
    final routeText = switch (place.target) {
      null => 'Авто · $exits',
      SplitTarget.bypass => exits == 'Мимо VPN' ? exits : 'Мимо VPN · $exits',
      SplitTarget.via => 'VPN · $exits',
    };
    final route = known
        ? PlaceButton(
            key: ValueKey('place-${app.exe}'),
            items: item,
            label: title,
            inlineText: routeText,
            routeColors: [for (final d in app.dests) destColor(d)],
            onCompare: () => showComparePathsDialog(
              context,
              CompareSubject(endpoints: endpointsForApp(app.exe, all), appExe: app.exe),
            ),
          )
        : _DestText(app.dests.first, label: exits);
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: title),
              if (app.group != null)
                TextSpan(
                  text: ' · ${app.group}',
                  style: const TextStyle(fontWeight: FontWeight.w400, color: RescueColors.subOnDeep),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: RescueColors.textOnDeep),
        ),
        const SizedBox(height: 3),
        Text(
          sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: RescueColors.subOnDeep),
        ),
      ],
    );
    return Semantics(
      expanded: open,
      child: InkWell(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: RescueColors.line, width: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: wide ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: _Tile(letter: known ? title.characters.first.toUpperCase() : '?'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: wide
                    ? name
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [name, const SizedBox(height: 3), route],
                      ),
              ),
              const SizedBox(width: 12),
              SizedBox(width: wide ? 110 : 36, child: numbers),
              if (wide) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 220,
                  child: Align(alignment: Alignment.centerLeft, child: route),
                ),
              ],
              if (known)
                GroupButton(
                  key: ValueKey('live-more-${app.exe}'),
                  items: item,
                  label: title,
                  onOpenGroup: onOpenGroup,
                  menuOnly: true,
                )
              else
                const SizedBox(width: 40),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка соединения под программой: адрес, почему так, трафик, куда ушло, «⋯» — направить сайт или IP.
class _ConnRow extends ConsumerWidget {
  const _ConnRow({super.key, required this.conn, required this.wide, required this.servers});

  final LiveConn conn;
  final bool wide;
  final RescueServers? servers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conn.connection;
    final split = ref.watch(splitTunnelProvider);
    final address = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: conn.address,
            style: const TextStyle(color: RescueColors.textOnDeep),
          ),
          TextSpan(
            text:
                '  ${c.host.isNotEmpty ? '${c.ip} · ' : ''}${c.network.toUpperCase()} ${c.port}${c.closed ? ' · закрыто' : ''}',
            style: const TextStyle(fontSize: 11, color: RescueColors.muted),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12),
    );
    final why = Text.rich(
      _reason(conn, servers),
      maxLines: wide ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: RescueColors.muted),
    );
    final bytes = Text(
      formatBytes(conn.bytes),
      maxLines: 1,
      textAlign: TextAlign.right,
      style: const TextStyle(fontSize: 12, color: RescueColors.subOnDeep, fontFeatures: [FontFeature.tabularFigures()]),
    );
    final site = c.host.isNotEmpty ? siteOf(c.host.toLowerCase()) : null;
    final more = MenuAnchor(
      menuChildren: [
        if (site != null)
          SubmenuButton(
            menuChildren: placeMenuItems(
              ref: ref,
              split: split,
              servers: servers,
              items: [(kind: SplitKind.domain, value: site)],
            ),
            child: Text('Сайт $site и поддомены'),
          ),
        if (c.ip.isNotEmpty)
          SubmenuButton(
            menuChildren: placeMenuItems(
              ref: ref,
              split: split,
              servers: servers,
              items: [(kind: SplitKind.ip, value: cidrOf(c.ip))],
            ),
            child: Text('Только IP ${c.ip}'),
          ),
        if (site != null) GroupMenuItem(item: (kind: SplitKind.domain, value: site), label: 'Сайт $site — в группу'),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Направить: ${site ?? c.ip}',
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        style: IconButton.styleFrom(minimumSize: const Size(36, 36), foregroundColor: RescueColors.subOnDeep),
        icon: const Icon(Icons.more_horiz_rounded, size: 20),
      ),
    );
    final Widget content;
    if (wide) {
      content = Row(
        children: [
          Expanded(flex: 5, child: address),
          const SizedBox(width: 12),
          Expanded(flex: 6, child: why),
          SizedBox(width: 76, child: bytes),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Align(alignment: Alignment.centerLeft, child: _DestText(conn.dest)),
          ),
          more,
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: address),
              more,
            ],
          ),
          why,
          const SizedBox(height: 4),
          Row(children: [_DestText(conn.dest), const SizedBox(width: 10), bytes]),
        ],
      );
    }
    return Opacity(
      opacity: c.closed ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(left: 34),
        padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: RescueColors.line, width: 0.5)),
        ),
        child: content,
      ),
    );
  }

  static TextSpan _reason(LiveConn conn, RescueServers? servers) {
    const bold = TextStyle(fontWeight: FontWeight.w700, color: RescueColors.subOnDeep);
    final hit = conn.hit;
    if (hit == null) {
      return TextSpan(
        children: [
          const TextSpan(text: 'Авто', style: bold),
          TextSpan(
            text: conn.dest is DirectDest
                ? ': общие правила → мимо (российское или домашняя сеть)'
                : ': общие правила → через VPN',
          ),
        ],
      );
    }
    final i = hit.item;
    final what = switch (i.kind) {
      SplitKind.app => 'программа ${appTitle(i.value)}',
      SplitKind.domain => 'сайт ${i.value}',
      SplitKind.ip => 'IP ${i.value.replaceFirst(RegExp(r'/(32|128)$'), '')}',
    };
    return TextSpan(
      children: [
        TextSpan(text: what, style: bold),
        if (hit.group != null) TextSpan(text: ' · группа «${hit.group}»'),
        if (hit.target == SplitTarget.via && hit.server == null && (servers?.several ?? false))
          const TextSpan(text: ' · сервер выбрала Шлюпка'),
      ],
    );
  }
}

/// Пункт меню «в группу» для одной записи (подменю групп).
class GroupMenuItem extends ConsumerWidget {
  const GroupMenuItem({super.key, required this.item, required this.label});

  final SplitRef item;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitTunnelProvider);
    final notifier = ref.read(splitTunnelProvider.notifier);
    final current = split.groupOf(item.kind, item.value);
    return SubmenuButton(
      menuChildren: [
        for (final g in split.groups)
          MenuItemButton(
            onPressed: current != null && sameGroupName(current, g.name)
                ? null
                : () => notifier.moveToGroup(g.name, [item]),
            child: Text(g.name),
          ),
        MenuItemButton(
          onPressed: () async {
            final name = await showGroupNameDialog(context, title: 'Новая группа');
            if (name != null) notifier.moveToGroup(name, [item]);
          },
          child: const Text('Новая группа…'),
        ),
      ],
      child: Text(label),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: RescueColors.line, borderRadius: BorderRadius.circular(10)),
    child: Text(
      letter,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RescueColors.textOnDeep),
    ),
  );
}

/// Пусто: текст и, если есть, кнопка.
class _Empty extends StatelessWidget {
  const _Empty({required this.text, this.action});

  final String text;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: RescueColors.subOnDeep),
        ),
        if (action case (final label, final onPressed)) ...[
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onPressed, child: Text(label)),
        ],
      ],
    ),
  );
}
