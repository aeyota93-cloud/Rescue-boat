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

const looseGroup = '';
const _panelWidth = 420.0;
typedef _Bucket = ({String name, SplitPlace place});

/// Перенос карточки меняет путь, перенос строки — её группу.
class _CardDrag {
  const _CardDrag(this.items);
  final List<SplitRef> items;
}

/// «Все правила»: доска по местам; при поиске — список записей.
class TunnelGroupsView extends HookConsumerWidget {
  const TunnelGroupsView({
    super.key,
    required this.entries,
    required this.titles,
    required this.query,
    required this.pinned,
    required this.openGroup,
  });
  final List<TunnelEntry> entries;
  final Map<String, String> titles;
  final String query;
  final bool pinned;

  /// Переход с «Сейчас в сети» открывает всю группу, карточка — своё место.
  final ValueNotifier<String?> openGroup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitTunnelProvider);
    final servers = ref.watch(rescueServersProvider);
    final selected = useState(const <String>{});
    final bucket = useState<_Bucket?>(null);
    final dragging = useState(false);
    useEffect(() {
      selected.value = const {};
      if (bucket.value?.name != openGroup.value) bucket.value = null;
      return null;
    }, [openGroup.value]);
    final listed = entries.where((e) => e.target != null || e.group != null).toList();
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final found =
          listed.where((e) => e.value.toLowerCase().contains(q) || _title(e, titles).toLowerCase().contains(q)).toList()
            ..sort((a, b) => _title(a, titles).toLowerCase().compareTo(_title(b, titles).toLowerCase()));
      final rows = [
        for (final e in found) _EntryRow(key: ValueKey('entry-${e.value}'), entry: e, titles: titles, showGroup: true),
      ];
      return DeepList(
        radius: 16,
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
    }
    final groups = <String, List<TunnelEntry>>{for (final g in split.groups) g.name: [], looseGroup: []};
    final buckets = <_Bucket, List<TunnelEntry>>{};
    for (final e in listed) {
      final name = e.group ?? looseGroup;
      groups.putIfAbsent(name, () => []).add(e);
    }
    // Порядок групп не зависит от того, какая программа только что вышла в сеть.
    for (final group in groups.entries) {
      for (final e in group.value) {
        final key = (name: group.key, place: split.placeOf(e.kind, e.value));
        buckets.putIfAbsent(key, () => []).add(e);
      }
    }
    final open = openGroup.value;
    final opened = open == null
        ? null
        : bucket.value == null
        ? groups[open]
        : buckets[bucket.value];
    if (open != null && (opened == null || opened.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (openGroup.value == open) openGroup.value = null;
      });
    }
    void close() {
      openGroup.value = null;
      bucket.value = null;
    }

    Widget cards(SplitPlace place, Color color) {
      final here = buckets.entries.where((b) => b.key.place == place);
      return Column(
        key: ValueKey('cards-${_placeKey(place)}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (here.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('Пока пусто', textAlign: TextAlign.center, style: RescueText.smallSecondary),
            ),
          for (final b in here)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _GroupCard(
                key: ValueKey('group-card-${b.key.name}-${_placeKey(place)}'),
                name: b.key.name,
                entries: b.value,
                total: groups[b.key.name]!.length,
                titles: titles,
                color: color,
                open: open == b.key.name && (bucket.value == null || bucket.value == b.key),
                onOpen: () {
                  selected.value = const {};
                  bucket.value = b.key;
                  openGroup.value = b.key.name;
                },
                onDrag: (v) => dragging.value = v,
              ),
            ),
        ],
      );
    }

    Widget section(SplitPlace place, String? title) {
      final count = listed.where((e) => split.placeOf(e.kind, e.value) == place).length;
      return _PlaceDrop(
        key: ValueKey('drop-${_placeKey(place)}'),
        place: place,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(title, style: RescueText.smallSecondary, overflow: TextOverflow.ellipsis),
                      ),
                      _Count(count, color: RescueColors.accent),
                    ],
                  ),
                ),
              cards(place, RescueColors.accent),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        final side = constraints.maxWidth >= 1280;
        final panel = opened != null && opened.isNotEmpty
            ? _GroupPanel(
                key: ValueKey('group-panel-$open'),
                name: open!,
                entries: opened,
                titles: titles,
                selected: selected,
                pinned: pinned,
                onClose: close,
                backLabel: side ? null : 'Все правила',
              )
            : null;
        if (panel != null && !side) return panel;
        final subdivide = listed.any((e) => e.server != null) || dragging.value;
        final assigned = listed.map((e) => e.server).whereType<String>().toSet();
        final tags = <String>{
          if (servers != null)
            for (final s in servers.servers)
              if (dragging.value || assigned.contains(s.tag)) s.tag,
          ...(assigned.toList()..sort()),
        };
        final columns = [
          for (final (place, title, color) in [
            (bypassPlace, 'Мимо VPN', RescueColors.info),
            (autoPlace, 'Авто', RescueColors.muted),
            (viaPlace, 'Через VPN', RescueColors.accent),
          ])
            _BoardColumn(
              key: ValueKey('column-${_placeKey(place)}'),
              title: title,
              place: place,
              color: color,
              narrow: narrow,
              count: listed.where((e) => e.target == place.target).length,
              child: place == viaPlace
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        section(viaPlace, subdivide ? 'Любой сервер' : null),
                        for (final tag in tags)
                          section((target: SplitTarget.via, server: tag), servers?.byTag(tag)?.name ?? tag),
                      ],
                    )
                  : cards(place, color),
            ),
        ];
        final board = narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final column in columns) Padding(padding: const EdgeInsets.only(bottom: 12), child: column),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < columns.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: columns[i]),
                  ],
                ],
              );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: pinned ? PinnedScroll(child: board) : board),
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
String _placeKey(SplitPlace place) => place.server ?? place.target?.name ?? 'auto';

class _Count extends StatelessWidget {
  const _Count(this.count, {required this.color});
  final int count;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
    child: Text(
      '$count',
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

class _PlaceDrop extends ConsumerWidget {
  const _PlaceDrop({super.key, required this.place, required this.child});
  final SplitPlace place;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) => DragTarget<_CardDrag>(
    onWillAcceptWithDetails: (_) => true,
    onAcceptWithDetails: (d) => ref.read(splitTunnelProvider.notifier).setPlace(d.data.items, place),
    builder: (context, candidates, _) => AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: candidates.isEmpty ? Colors.transparent : RescueColors.accentTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: candidates.isEmpty ? Colors.transparent : RescueColors.accent),
      ),
      child: child,
    ),
  );
}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    super.key,
    required this.title,
    required this.place,
    required this.count,
    required this.color,
    required this.narrow,
    required this.child,
  });
  final String title;
  final SplitPlace place;
  final int count;
  final Color color;
  final bool narrow;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final heading = Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(color: RescueColors.text, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        _Count(count, color: color),
      ],
    );
    return _PlaceDrop(
      place: place,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: RescueColors.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: RescueColors.line),
        ),
        child: narrow
            ? ExpansionTile(
                key: PageStorageKey('expand-${_placeKey(place)}'),
                initiallyExpanded: true,
                tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: const Border(),
                collapsedShape: const Border(),
                title: heading,
                children: [child],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                    child: Semantics(header: true, child: heading),
                  ),
                  child,
                ],
              ),
      ),
    );
  }
}

class _GroupCard extends ConsumerWidget {
  const _GroupCard({
    super.key,
    required this.name,
    required this.entries,
    required this.total,
    required this.titles,
    required this.color,
    required this.open,
    required this.onOpen,
    required this.onDrag,
  });
  final String name;
  final List<TunnelEntry> entries;
  final int total;
  final Map<String, String> titles;
  final Color color;
  final bool open;
  final VoidCallback onOpen;
  final ValueChanged<bool> onDrag;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitTunnelProvider);
    final servers = ref.watch(rescueServersProvider);
    final notifier = ref.read(splitTunnelProvider.notifier);
    final loose = name == looseGroup;
    final title = loose ? 'Без группы' : name;
    final label = !loose && entries.length != total ? '$title · ${entries.length} из $total' : title;
    final items = [for (final e in entries) _ref(e)];
    final errors = entries.fold(0, (s, e) => s + e.errors);
    final online = entries.any((e) => e.online);
    final card = Material(
      color: RescueColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: open ? RescueColors.accent : RescueColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              loose ? 'Б' : title.characters.first.toUpperCase(),
                              style: TextStyle(color: color, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: RescueColors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          MenuAnchor(
                            menuChildren: [
                              SubmenuButton(
                                menuChildren: placeMenuItems(ref: ref, split: split, servers: servers, items: items),
                                child: const Text('Переложить в'),
                              ),
                              if (!loose) ...[
                                MenuItemButton(
                                  onPressed: () async {
                                    final n = await showGroupNameDialog(
                                      context,
                                      title: 'Переименовать группу',
                                      initial: name,
                                    );
                                    if (n != null) notifier.renameGroup(name, n);
                                  },
                                  child: const Text('Переименовать…'),
                                ),
                                MenuItemButton(
                                  onPressed: () => notifier.deleteGroup(name),
                                  child: const Text('Удалить группу (записи останутся)'),
                                ),
                              ],
                            ],
                            builder: (context, controller, _) => IconButton(
                              tooltip: 'Группа $title: ещё',
                              onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(40, 40),
                                foregroundColor: RescueColors.muted,
                              ),
                              icon: const Icon(Icons.more_horiz_rounded, size: 20),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entries.take(4).map((e) => _title(e, titles)).join(', ') + (entries.length > 4 ? '…' : ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RescueText.smallSecondary,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _Count(entries.length, color: color),
                          if (online)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(color: Color(0xFF72CC98), shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 5),
                                const Text('сейчас', style: TextStyle(fontSize: 12, color: RescueColors.muted)),
                              ],
                            ),
                          FailBadge(errors),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      label: '$label, ${entries.length} ${pluralRu(entries.length, 'запись', 'записи', 'записей')}',
      child: Draggable<_CardDrag>(
        data: _CardDrag(items),
        onDragStarted: () => onDrag(true),
        onDragEnd: (_) => onDrag(false),
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: 220,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: RescueColors.card,
              border: Border.all(color: RescueColors.accent),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text('$label · ${entries.length}', style: RescueText.body),
          ),
        ),
        childWhenDragging: Opacity(opacity: .35, child: card),
        child: DragTarget<List<SplitRef>>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (d) => loose ? notifier.removeFromGroup(d.data) : notifier.moveToGroup(name, d.data),
          builder: (context, candidates, _) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: candidates.isEmpty ? null : Border.all(color: RescueColors.accent, width: 2),
            ),
            child: card,
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

  /// Узкое окно: панель вместо доски, сверху «← Все правила».
  final String? backLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = name == looseGroup ? 'Без группы' : 'Группа «$name»';
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
}

/// Строка записи: отметка, название, группа, путь. [dragItems] — что перетаскивать (null — нельзя).
class _EntryRow extends ConsumerWidget {
  const _EntryRow({
    super.key,
    required this.entry,
    required this.titles,
    this.showGroup = false,
    this.shortGroup = false,
    this.selected,
    this.onSelected,
    this.dragItems,
  });

  final TunnelEntry entry;
  final Map<String, String> titles;
  final bool showGroup;

  /// В открытой группе — «Перенести» вместо её имени.
  final bool shortGroup;

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
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: RescueColors.muted),
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
    final row = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: const BoxDecoration(
          color: RescueColors.card,
          border: Border(left: BorderSide(color: RescueColors.info, width: 4)),
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
