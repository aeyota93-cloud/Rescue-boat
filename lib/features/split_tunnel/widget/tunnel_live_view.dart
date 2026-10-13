import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/common/pinned_scroll.dart';
import 'package:hiddify/features/compare/model/compare_target.dart';
import 'package:hiddify/features/compare/widget/compare_paths_dialog.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
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

/// Ширина, с которой строки показываются колонками; уже — в две строчки.
const liveWideFrom = 820.0;

enum _LiveMode { apps, groups }

/// Шлюпка: вкладка «Сейчас в сети» (docs/redesign/tunnel-v3.md). Сводка по реальным выходам,
/// фильтры, программы с соединениями: группа, куда ушло, почему. Плашка пути у программы —
/// правило для всей программы, «⋯» у соединения — для его сайта или IP.
class TunnelLiveView extends HookConsumerWidget {
  const TunnelLiveView({
    super.key,
    required this.connections,
    required this.errors,
    required this.titles,
    required this.query,
    required this.pinned,
    required this.onOpenGroup,
    required this.onShowGroups,
  });

  /// null — ядро не запущено (VPN выключен).
  final List<NetConnection>? connections;
  final List<ErrorGroup> errors;

  /// Описания запущенных программ — для названий.
  final Map<String, String> titles;
  final String query;
  final bool pinned;
  final ValueChanged<String> onOpenGroup;
  final VoidCallback onShowGroups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = useState(LiveFilter.all);
    final mode = useState(_LiveMode.apps);
    final open = useState(const <String>{});
    final split = ref.watch(splitTunnelProvider);
    final servers = ref.watch(rescueServersProvider);
    final all = connections;

    if (all == null) {
      return _Empty(
        text: 'VPN выключен — соединений не видно. Включите VPN, чтобы видеть, что куда идёт прямо сейчас.',
        action: ('Открыть группы', onShowGroups),
      );
    }

    String titleOf(String exe) => appTitle(exe, titles);
    final apps = buildLiveApps(split, all, servers, filter: filter.value, query: query, titleOf: titleOf);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= liveWideFrom;
        final rows = <Widget>[];
        void addApp(LiveApp app) {
          final key = app.exe.toLowerCase();
          final isOpen = open.value.contains(key);
          rows.add(
            _AppRow(
              key: ValueKey('live-app-${app.exe}'),
              app: app,
              title: titleOf(app.exe),
              wide: wide,
              open: isOpen,
              errors: app.exe.isEmpty ? 0 : errorsFor(SplitKind.app, app.exe, errors),
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

        if (mode.value == _LiveMode.apps) {
          apps.forEach(addApp);
        } else {
          final byGroup = <String?, List<LiveApp>>{};
          for (final a in apps) {
            (byGroup[a.group] ??= []).add(a);
          }
          final order = [
            for (final g in split.groups)
              if (byGroup.containsKey(g.name)) g.name,
            if (byGroup.containsKey(null)) null,
          ];
          for (final g in order) {
            rows.add(_SectionHeader(key: ValueKey('live-section-${g ?? ''}'), group: g, onOpenGroup: onOpenGroup));
            byGroup[g]!.forEach(addApp);
          }
        }

        final summary = _Summary(connections: all, servers: servers);
        final tools = Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            FilterChips<LiveFilter>(
              options: const [
                (LiveFilter.all, 'Все'),
                (LiveFilter.vpn, 'Через VPN'),
                (LiveFilter.direct, 'Мимо'),
                (LiveFilter.auto, 'Без правила'),
              ],
              selected: filter.value,
              onSelected: (f) => filter.value = f,
            ),
            SizedBox(
              width: constraints.maxWidth < 300 ? constraints.maxWidth : 300,
              child: PillSegmented<_LiveMode>(
                segments: const [
                  PillSegment(value: _LiveMode.apps, label: 'По программам'),
                  PillSegment(value: _LiveMode.groups, label: 'По группам'),
                ],
                value: mode.value,
                onChanged: (m) => mode.value = m,
                semanticLabel: 'Как разложить',
                expand: true,
                fontSize: 12,
                letterSpacing: 0,
              ),
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
        final list = DeepList(
          radius: 28,
          semanticLabel: 'Программы в сети',
          spacing: 0,
          children: [
            if (rows.isEmpty)
              empty
            else if (pinned)
              Expanded(
                child: PinnedList(
                  key: const ValueKey('live-rows'),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => rows[i],
                ),
              )
            else
              ...rows,
          ],
        );
        const note = Text(
          'Цветная метка — куда соединение ушло на самом деле. Плашка пути у программы меняет правило '
          'для всей программы, меню у соединения — только для его сайта или IP.',
          style: RescueText.caption,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: pinned ? MainAxisSize.max : MainAxisSize.min,
          children: [
            summary,
            const SizedBox(height: 12),
            tools,
            const SizedBox(height: 12),
            if (pinned) Expanded(child: list) else list,
            const SizedBox(height: 10),
            note,
          ],
        );
      },
    );
  }
}

/// Сводка: сколько соединений и полоска «куда ушли».
class _Summary extends StatelessWidget {
  const _Summary({required this.connections, required this.servers});

  final List<NetConnection> connections;
  final RescueServers? servers;

  @override
  Widget build(BuildContext context) {
    final parts = liveSummary(connections, servers);
    final total = parts.fold(0, (s, p) => s + p.$2);
    final programs = {for (final c in connections.where((c) => !c.closed)) c.exe.toLowerCase()}.length;
    return RescueCard.deep(
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      semanticLabel:
          'Сейчас $total ${pluralRu(total, 'соединение', 'соединения', 'соединений')}: '
          '${[for (final (d, n) in parts) '${destLabel(d)} $n'].join(', ')}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Text(
                  '$total ${pluralRu(total, 'соединение', 'соединения', 'соединений')}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: RescueColors.textOnDeep),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '$programs ${pluralRu(programs, 'программа', 'программы', 'программ')} · обновляется каждые 2 секунды',
                    style: const TextStyle(fontSize: 12, color: RescueColors.subOnDeep),
                  ),
                ),
              ],
            ),
            if (total > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 10,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, (d, n)) in parts.indexed) ...[
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          flex: n,
                          child: ColoredBox(color: destColor(d)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  for (final (d, n) in parts)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(color: destColor(d), borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${destLabel(d)} · $n',
                          style: const TextStyle(fontSize: 12, color: RescueColors.subOnDeep),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Строка программы: название, группа, сколько соединений и трафика, куда ушли, плашка пути.
class _AppRow extends ConsumerWidget {
  const _AppRow({
    super.key,
    required this.app,
    required this.title,
    required this.wide,
    required this.open,
    required this.errors,
    required this.all,
    required this.onToggle,
    required this.onOpenGroup,
  });

  final LiveApp app;
  final String title;
  final bool wide;
  final bool open;
  final int errors;
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

    final name = Row(
      children: [
        Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 20, color: RescueColors.subOnDeep),
        const SizedBox(width: 6),
        _Tile(letter: known ? title.characters.first.toUpperCase() : '?'),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: RescueColors.textOnDeep),
                    ),
                  ),
                  Flexible(child: FailBadge(errors)),
                ],
              ),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: RescueColors.subOnDeep),
              ),
            ],
          ),
        ),
      ],
    );
    final toggle = Semantics(
      button: true,
      expanded: open,
      label:
          '$title, $count, ${formatBytes(app.bytes)}${app.group == null ? '' : ', группа ${app.group}'}, '
          'куда ушли: ${[for (final d in app.dests) destLabel(d)].join(', ')}',
      onTap: onToggle,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onToggle,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: name),
        ),
      ),
    );
    final group = known
        ? GroupButton(key: ValueKey('group-btn-${app.exe}'), items: item, label: title, onOpenGroup: onOpenGroup)
        : null;
    final numbers = Text(
      '$count · ${formatBytes(app.bytes)}',
      maxLines: 1,
      style: const TextStyle(fontSize: 12, color: RescueColors.subOnDeep, fontFeatures: [FontFeature.tabularFigures()]),
    );
    final dests = Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children: [for (final d in app.dests) DestPill(d)],
    );
    final place = known
        ? PlaceButton(
            key: ValueKey('place-${app.exe}'),
            items: item,
            label: title,
            onCompare: () => showComparePathsDialog(
              context,
              CompareSubject(endpoints: endpointsForApp(app.exe, all), appExe: app.exe),
            ),
          )
        : null;

    final Widget content;
    if (wide) {
      content = Row(
        children: [
          Expanded(child: toggle),
          const SizedBox(width: 10),
          SizedBox(
            width: 170,
            child: Align(alignment: Alignment.centerLeft, child: group),
          ),
          SizedBox(width: 150, child: ExcludeSemantics(child: numbers)),
          SizedBox(width: 190, child: ExcludeSemantics(child: dests)),
          const SizedBox(width: 10),
          SizedBox(
            width: 132,
            child: Align(alignment: Alignment.centerRight, child: place),
          ),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: toggle),
              ?place,
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 4),
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ?group,
                ExcludeSemantics(child: numbers),
                ExcludeSemantics(child: dests),
              ],
            ),
          ),
        ],
      );
    }
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: RescueColors.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: content,
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
            child: Align(alignment: Alignment.centerLeft, child: DestPill(conn.dest)),
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
          Row(children: [DestPill(conn.dest), const SizedBox(width: 10), bytes]),
        ],
      );
    }
    return Opacity(
      opacity: c.closed ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(left: 34),
        padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: RescueColors.line2)),
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

/// Заголовок раздела в режиме «По группам».
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.group, required this.onOpenGroup});

  final String? group;
  final ValueChanged<String> onOpenGroup;

  @override
  Widget build(BuildContext context) {
    final g = group;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
      child: Row(
        children: [
          Flexible(
            child: Semantics(
              header: true,
              child: Text(
                (g ?? 'Без группы').toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: RescueColors.subOnDeep,
                ),
              ),
            ),
          ),
          if (g != null)
            TextButton(
              onPressed: () => onOpenGroup(g),
              style: TextButton.styleFrom(foregroundColor: RescueColors.accent),
              child: const Text('открыть группу', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
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
  Widget build(BuildContext context) => RescueCard.deep(
    radius: 24,
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
