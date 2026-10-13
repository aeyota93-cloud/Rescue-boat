import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/common/pinned_scroll.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/servers/model/rescue_servers.dart';
import 'package:hiddify/features/servers/notifier/failover.dart';
import 'package:hiddify/features/split_tunnel/model/app_names.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/model/tunnel_rows.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hiddify/features/split_tunnel/widget/place_menu.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Имя «группы» записей без группы на этой вкладке.
const looseGroup = '';

/// С этой ширины открытая группа — панелью справа от карточек; уже — вместо карточек.
const _sidePanelFrom = 1000.0;
const _panelWidth = 460.0;
const _cardWidth = 280.0;

/// Шлюпка: вкладка «Группы» (docs/redesign/tunnel-v3.md). Карточка группы — путь всем записям
/// сразу («Авто / Мимо / VPN», сервер — ▾), «Выровнять» при разных путях, «Открыть» — записи
/// сбоку: у каждой свой путь и своя группа, можно отметить несколько или перетащить на карточку.
/// При поиске карточек нет — найденные записи одним списком.
class TunnelGroupsView extends HookConsumerWidget {
  const TunnelGroupsView({
    super.key,
    required this.entries,
    required this.titles,
    required this.query,
    required this.pinned,
    required this.openGroup,
  });

  /// Записи списков и групп (строки [buildTunnelRows]) с числом соединений и ошибок.
  final List<TunnelEntry> entries;
  final Map<String, String> titles;
  final String query;
  final bool pinned;

  /// Открытая группа (её записи сбоку); [looseGroup] — «Без группы»; null — ни одна.
  final ValueNotifier<String?> openGroup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitTunnelProvider);
    final selected = useState(const <String>{});
    useEffect(() {
      selected.value = const {};
      return null;
    }, [openGroup.value]);

    // Программы в сети, которых нет в списках и группах, живут на «Сейчас в сети».
    final listed = entries.where((e) => e.target != null || e.group != null).toList();
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final found = listed
          .where((e) => e.value.toLowerCase().contains(q) || _title(e, titles).toLowerCase().contains(q))
          .toList();
      final rows = [
        for (final e in found) _EntryRow(key: ValueKey('entry-${e.value}'), entry: e, titles: titles, showGroup: true),
      ];
      final list = DeepList(
        radius: 28,
        spacing: 0,
        semanticLabel: 'Найденные записи',
        children: [
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Ничего не нашлось.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: RescueColors.subOnDeep),
              ),
            )
          else if (pinned)
            Expanded(
              child: PinnedList(itemCount: rows.length, itemBuilder: (_, i) => rows[i]),
            )
          else
            ...rows,
        ],
      );
      return list;
    }

    final byGroup = <String, List<TunnelEntry>>{for (final g in split.groups) g.name: [], looseGroup: []};
    for (final e in listed) {
      byGroup[e.group ?? looseGroup]?.add(e);
    }
    byGroup.removeWhere((_, list) => list.isEmpty);
    final open = openGroup.value;
    if (open != null && !byGroup.containsKey(open)) {
      // Группу удалили или в ней не осталось записей — закрываем.
      WidgetsBinding.instance.addPostFrameCallback((_) => openGroup.value = null);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth >= _sidePanelFrom;
        final panelOpen = open != null && byGroup.containsKey(open);
        // В закреплённом виде справа от сетки — место под полосу прокрутки (PinnedScroll).
        final gridWidth =
            (side && panelOpen ? constraints.maxWidth - _panelWidth - 16 : constraints.maxWidth) - (pinned ? 12 : 0);
        final cols = ((gridWidth + 12) / (_cardWidth + 12)).floor().clamp(1, 6);
        final cardWidth = (gridWidth - 12 * (cols - 1)) / cols;
        final grid = Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final MapEntry(key: name, value: list) in byGroup.entries)
              SizedBox(
                width: cardWidth,
                child: _GroupCard(
                  key: ValueKey('group-card-$name'),
                  name: name,
                  entries: list,
                  titles: titles,
                  open: open == name,
                  onOpen: () => openGroup.value = open == name ? null : name,
                ),
              ),
          ],
        );
        final panel = panelOpen
            ? _GroupPanel(
                key: ValueKey('group-panel-$open'),
                name: open,
                entries: byGroup[open]!,
                titles: titles,
                selected: selected,
                pinned: pinned,
                onClose: () => openGroup.value = null,
                backLabel: side ? null : 'Все группы',
              )
            : null;

        if (panel != null && !side) return panel;
        if (pinned) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: PinnedScroll(child: grid)),
              if (panel != null) ...[const SizedBox(width: 16), SizedBox(width: _panelWidth, child: panel)],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: grid),
            if (panel != null) ...[const SizedBox(width: 16), SizedBox(width: _panelWidth, child: panel)],
          ],
        );
      },
    );
  }
}

String _title(TunnelEntry e, Map<String, String> titles) => switch (e.kind) {
  SplitKind.app => appTitle(e.value, titles),
  SplitKind.ip => e.value.replaceFirst(RegExp(r'/(32|128)$'), ''),
  SplitKind.domain => e.value,
};

SplitRef _ref(TunnelEntry e) => (kind: e.kind, value: e.value);
String _key(TunnelEntry e) => '${e.kind.name}|${e.value}';

/// Карточка группы.
class _GroupCard extends ConsumerWidget {
  const _GroupCard({
    super.key,
    required this.name,
    required this.entries,
    required this.titles,
    required this.open,
    required this.onOpen,
  });

  final String name;
  final List<TunnelEntry> entries;
  final Map<String, String> titles;
  final bool open;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitTunnelProvider);
    final servers = ref.watch(rescueServersProvider);
    final notifier = ref.read(splitTunnelProvider.notifier);
    final loose = name == looseGroup;
    final title = loose ? 'Без группы' : name;
    final items = [for (final e in entries) _ref(e)];
    final place = split.commonPlace(items);
    final choice = switch (place) {
      null => null,
      (target: null, server: _) => RouteChoice.auto,
      (target: SplitTarget.bypass, server: _) => RouteChoice.bypass,
      (target: SplitTarget.via, server: _) => RouteChoice.vpn,
    };
    final several = servers != null && servers.several;
    final known = entries.where((e) => e.connections != null);
    final conns = known.isEmpty ? null : known.fold(0, (s, e) => s + e.connections!);
    final errors = entries.fold(0, (s, e) => s + e.errors);
    final count = '${entries.length} ${pluralRu(entries.length, 'запись', 'записи', 'записей')}';

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: RescueColors.card, borderRadius: BorderRadius.circular(11)),
          child: loose
              ? const Icon(Icons.more_horiz_rounded, size: 18, color: RescueColors.accent)
              : Text(
                  title.characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: RescueColors.accent),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: RescueColors.textOnDeep),
              ),
              Text(count, style: const TextStyle(fontSize: 12, color: RescueColors.subOnDeep)),
            ],
          ),
        ),
        if (!loose)
          MenuAnchor(
            menuChildren: [
              MenuItemButton(
                onPressed: () async {
                  final n = await showGroupNameDialog(context, title: 'Переименовать группу', initial: name);
                  if (n != null) notifier.renameGroup(name, n);
                },
                child: const Text('Переименовать…'),
              ),
              MenuItemButton(
                onPressed: () => notifier.deleteGroup(name),
                child: const Text('Удалить группу (записи останутся)'),
              ),
            ],
            builder: (context, controller, _) => IconButton(
              tooltip: 'Группа $title: ещё',
              onPressed: () => controller.isOpen ? controller.close() : controller.open(),
              style: IconButton.styleFrom(minimumSize: const Size(36, 36), foregroundColor: RescueColors.subOnDeep),
              icon: const Icon(Icons.more_horiz_rounded, size: 20),
            ),
          ),
      ],
    );
    final preview = Text(
      entries.take(4).map((e) => _title(e, titles)).join(', ') + (entries.length > 4 ? '…' : ''),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: RescueColors.subOnDeep),
    );
    final route = RouteSwitch(
      width: null,
      value: choice,
      semanticLabel: 'Куда идёт группа $title',
      onChanged: (c) => notifier.setPlace(items, switch (c) {
        RouteChoice.auto => autoPlace,
        RouteChoice.bypass => bypassPlace,
        RouteChoice.vpn => viaPlace,
      }),
    );
    // Все через VPN и серверов несколько — какой: «Любой» (выберет Шлюпка) или конкретный.
    final pinnedTag = place?.server;
    final server = choice == RouteChoice.vpn && several
        ? Row(
            children: [
              const Text('Сервер:', style: TextStyle(fontSize: 12, color: RescueColors.subOnDeep)),
              const SizedBox(width: 4),
              MenuAnchor(
                menuChildren: [
                  for (final (p, label) in <(SplitPlace, String)>[
                    (viaPlace, 'Любой — выберет Шлюпка'),
                    for (final s in servers.servers) ((target: SplitTarget.via, server: s.tag), s.name),
                  ])
                    MenuItemButton(
                      leadingIcon: place == p
                          ? const Icon(Icons.check_rounded, size: 18, color: RescueColors.accent)
                          : const SizedBox(width: 18),
                      onPressed: () => notifier.setPlace(items, p),
                      child: Text(label),
                    ),
                ],
                builder: (context, controller, _) => TextButton(
                  key: ValueKey('group-server-$name'),
                  onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                  style: TextButton.styleFrom(
                    foregroundColor: RescueColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(44, 32),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        pinnedTag == null ? 'Любой' : (servers.byTag(pinnedTag)?.name ?? 'Любой'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      const Icon(Icons.expand_more_rounded, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          )
        : null;
    final mixed = place == null
        ? Row(
            children: [
              Expanded(
                child: Text(
                  'Разные пути: ${describePlaces(split, items, servers)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: RescueColors.warn),
                ),
              ),
              MenuAnchor(
                menuChildren: placeMenuItems(ref: ref, split: split, servers: servers, items: items),
                builder: (context, controller, _) => TextButton(
                  onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                  style: TextButton.styleFrom(foregroundColor: RescueColors.accent),
                  child: const Text('Выровнять'),
                ),
              ),
            ],
          )
        : null;
    final footer = Row(
      children: [
        Expanded(
          child: Row(
            children: [
              if (conns != null && conns > 0) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(color: RescueColors.accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  switch (conns) {
                    null => '',
                    0 => 'не в сети',
                    final n => '$n ${pluralRu(n, 'соединение', 'соединения', 'соединений')}',
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: RescueColors.subOnDeep),
                ),
              ),
              Flexible(child: FailBadge(errors)),
            ],
          ),
        ),
        TextButton(
          key: ValueKey('group-open-$name'),
          onPressed: onOpen,
          style: TextButton.styleFrom(foregroundColor: RescueColors.textOnDeep),
          child: Text(open ? 'Закрыть' : 'Открыть'),
        ),
      ],
    );

    return DragTarget<List<SplitRef>>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => loose ? notifier.removeFromGroup(d.data) : notifier.moveToGroup(name, d.data),
      builder: (context, candidate, _) => Semantics(
        container: true,
        label: 'Группа $title, $count',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 6),
          decoration: BoxDecoration(
            color: RescueColors.deep,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: candidate.isNotEmpty || open ? RescueColors.accent : RescueColors.line,
              width: candidate.isNotEmpty ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 8),
              Padding(padding: const EdgeInsets.only(right: 6), child: preview),
              const SizedBox(height: 10),
              Padding(padding: const EdgeInsets.only(right: 6), child: route),
              ?server,
              if (mixed != null) ...[const SizedBox(height: 4), mixed],
              const SizedBox(height: 2),
              footer,
            ],
          ),
        ),
      ),
    );
  }
}

/// Записи открытой группы: у каждой свой путь и группа; можно отметить несколько.
class _GroupPanel extends ConsumerWidget {
  const _GroupPanel({
    super.key,
    required this.name,
    required this.entries,
    required this.titles,
    required this.selected,
    required this.pinned,
    required this.onClose,
    this.backLabel,
  });

  final String name;
  final List<TunnelEntry> entries;
  final Map<String, String> titles;
  final ValueNotifier<Set<String>> selected;
  final bool pinned;
  final VoidCallback onClose;

  /// Узкое окно: панель вместо карточек, сверху «← Все группы».
  final String? backLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitTunnelProvider);
    final title = name == looseGroup ? 'Без группы' : 'Группа «$name»';
    final items = [for (final e in entries) _ref(e)];
    final mixed = name != looseGroup && split.commonPlace(items) == null;
    final majority = mixed ? _majority(split, items) : null;
    final picked = [
      for (final e in entries)
        if (selected.value.contains(_key(e))) _ref(e),
    ];
    final all = entries.isNotEmpty && picked.length == entries.length;

    final rows = <Widget>[
      for (final e in entries)
        _EntryRow(
          key: ValueKey('entry-${e.value}'),
          entry: e,
          titles: titles,
          showGroup: true,
          shortGroup: name != looseGroup,
          differs: majority != null && split.placeOf(e.kind, e.value) != majority,
          selected: selected.value.contains(_key(e)),
          onSelected: (v) => selected.value = v ? {...selected.value, _key(e)} : ({...selected.value}..remove(_key(e))),
          dragItems: () => selected.value.contains(_key(e)) && picked.length > 1 ? picked : [_ref(e)],
        ),
    ];
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (backLabel != null)
              TextButton.icon(
                onPressed: onClose,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(backLabel!),
                style: TextButton.styleFrom(foregroundColor: RescueColors.textOnDeep),
              ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: RescueColors.textOnDeep),
                ),
              ),
            ),
            if (backLabel == null)
              IconButton(
                tooltip: 'Закрыть',
                onPressed: onClose,
                style: IconButton.styleFrom(foregroundColor: RescueColors.subOnDeep),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
        const Text(
          'У каждой записи свой путь. Кнопка с пунктиром — группа: перенести, в новую, убрать. '
          'Запись можно перетащить на карточку группы.',
          style: TextStyle(fontSize: 12, color: RescueColors.muted),
        ),
        if (picked.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('selection-bar'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: RescueColors.card, borderRadius: BorderRadius.circular(12)),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Выбрано ${picked.length}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: RescueColors.textOnDeep),
                ),
                GroupButton(key: const ValueKey('selection-group'), items: picked, label: 'выбранные'),
                PlaceButton(key: const ValueKey('selection-place'), items: picked, label: 'выбранные', compact: true),
                TextButton(
                  onPressed: () => selected.value = const {},
                  style: TextButton.styleFrom(foregroundColor: RescueColors.subOnDeep),
                  child: const Text('Снять'),
                ),
              ],
            ),
          ),
        ],
        CheckboxListTile(
          key: const ValueKey('select-all'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: all,
          onChanged: (v) => selected.value = v ?? false ? {for (final e in entries) _key(e)} : const {},
          title: const Text('Отметить все', style: TextStyle(fontSize: 12, color: RescueColors.subOnDeep)),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: RescueColors.deep,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RescueColors.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: pinned ? MainAxisSize.max : MainAxisSize.min,
        children: [
          head,
          if (pinned)
            Expanded(
              child: PinnedList(itemCount: rows.length, itemBuilder: (_, i) => rows[i]),
            )
          else
            ...rows,
        ],
      ),
    );
  }

  static SplitPlace? _majority(SplitTunnel split, List<SplitRef> items) {
    final counts = <SplitPlace, int>{};
    for (final i in items) {
      final p = split.placeOf(i.kind, i.value);
      counts[p] = (counts[p] ?? 0) + 1;
    }
    SplitPlace? best;
    for (final e in counts.entries) {
      if (best == null || e.value > counts[best]!) best = e.key;
    }
    return best;
  }
}

/// Строка записи: отметка, название, группа, путь. [dragItems] — что перетаскивать (null — нельзя).
class _EntryRow extends ConsumerWidget {
  const _EntryRow({
    super.key,
    required this.entry,
    required this.titles,
    this.showGroup = false,
    this.shortGroup = false,
    this.differs = false,
    this.selected,
    this.onSelected,
    this.dragItems,
  });

  final TunnelEntry entry;
  final Map<String, String> titles;
  final bool showGroup;

  /// В открытой группе — «Перенести» вместо её имени.
  final bool shortGroup;

  /// Путь не как у большинства в группе.
  final bool differs;
  final bool? selected;
  final ValueChanged<bool>? onSelected;
  final List<SplitRef> Function()? dragItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = entry;
    final title = _title(e, titles);
    final servers = ref.watch(rescueServersProvider);
    final detail = [
      switch (e.kind) {
        SplitKind.app => e.value,
        SplitKind.domain => 'сайт и поддомены',
        SplitKind.ip when isHomeNetwork(e.value) => 'домашняя сеть',
        SplitKind.ip when e.value.endsWith('/32') || e.value.endsWith('/128') => 'один адрес',
        SplitKind.ip => 'сеть',
      },
      if (e.server case final tag?) serverPlaceLabel(tag, servers),
      if (e.online) '${e.connections} ${pluralRu(e.connections!, 'соединение', 'соединения', 'соединений')}',
    ].join(' · ');
    final name = Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: RescueColors.line, borderRadius: BorderRadius.circular(8)),
          child: Text(
            e.kind == SplitKind.ip ? '#' : title.characters.first.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: RescueColors.textOnDeep),
          ),
        ),
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
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: RescueColors.textOnDeep),
                    ),
                  ),
                  Flexible(child: FailBadge(e.errors)),
                ],
              ),
              Text(
                differs ? '$detail · не как у группы' : detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: differs ? RescueColors.warn : RescueColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
    final item = [_ref(e)];
    final selected = this.selected;
    final check = selected == null
        ? null
        : Checkbox(value: selected, onChanged: (v) => onSelected?.call(v ?? false), semanticLabel: 'Отметить $title');
    final group = showGroup
        ? GroupButton(
            key: ValueKey('group-btn-${e.value}'),
            items: item,
            label: title,
            maxWidth: 120,
            short: shortGroup,
          )
        : null;
    final place = PlaceButton(key: ValueKey('place-${e.value}'), items: item, label: title, compact: true);
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: RescueColors.line)),
      ),
      // Узко (панель вместо карточек на маленьком окне) — кнопки второй строкой.
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 380
            ? Row(
                children: [
                  ?check,
                  Expanded(child: name),
                  const SizedBox(width: 6),
                  if (group != null) ...[group, const SizedBox(width: 6)],
                  place,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ?check,
                      Expanded(child: name),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: EdgeInsets.only(left: check == null ? 38 : 86),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [?group, place]),
                  ),
                ],
              ),
      ),
    );
    final drag = dragItems;
    if (drag == null) return row;
    return Draggable<List<SplitRef>>(
      data: drag(),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: RescueColors.card,
        borderRadius: BorderRadius.circular(10),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            drag().length > 1 ? '${drag().length} записей' : title,
            style: const TextStyle(fontSize: 13, color: RescueColors.textOnDeep, decoration: TextDecoration.none),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: row),
      child: row,
    );
  }
}
