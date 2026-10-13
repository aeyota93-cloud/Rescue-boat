import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/servers/notifier/failover.dart';
import 'package:hiddify/features/split_tunnel/data/running_apps.dart';
import 'package:hiddify/features/split_tunnel/model/app_names.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/model/tunnel_rows.dart';
import 'package:hiddify/features/split_tunnel/notifier/live_connections_notifier.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hiddify/features/split_tunnel/widget/place_menu.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: окна туннеля (docs/redesign/tunnel-v3.md) — «Добавить» (вписать или из запущенных,
/// сразу с группой и путём) и «Новая группа» (название и записи).

/// Закладки окна «Добавить».
enum AddTab { type, running }

/// Значение «+ Новая…» среди групп окна «Добавить».
const _newGroup = '\u0000new';

/// Путь «как у группы» среди путей окна «Добавить».
const _likeGroup = 'group';

SplitPlace _placeOfKey(String key) => switch (key) {
  'auto' => autoPlace,
  'bypass' => bypassPlace,
  'via' => viaPlace,
  _ => (target: SplitTarget.via, server: key.substring('server:'.length)),
};

/// Окно «Добавить»: записи, группа и путь. Добавляет само (одним сохранением).
Future<void> showAddDialog(BuildContext context, {AddTab tab = AddTab.type, String? group}) => showDialog<void>(
  context: context,
  builder: (_) => _AddDialog(tab: tab, group: group),
);

class _AddDialog extends HookConsumerWidget {
  const _AddDialog({required this.tab, required this.group});

  final AddTab tab;
  final String? group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitTunnelProvider);
    final servers = ref.watch(rescueServersProvider);
    final currentTab = useState(tab);
    final text = useTextEditingController();
    useListenable(text);
    final newName = useTextEditingController();
    useListenable(newName);
    final picked = useState(const <String>{});
    final groupKey = useState(group == null || split.group(group!) == null ? '' : split.group(group!)!.name);
    final placeKey = useState(groupKey.value.isEmpty ? 'auto' : _likeGroup);
    final running = ref.watch(runningAppsProvider);
    final query = useState('');

    // Записи: вписанные (по одной на строку или через запятую) или отмеченные запущенные.
    final skipped = <String>[];
    final items = <SplitRef>[];
    if (currentTab.value == AddTab.type) {
      for (final raw in text.text.split(RegExp(r'[\r\n,;]+'))) {
        if (raw.trim().isEmpty) continue;
        final item = parseSplitItem(raw);
        if (item == null) {
          skipped.add(raw.trim());
        } else if (!items.any((i) => i.kind == item.kind && sameItem(i.kind, i.value, item.value))) {
          items.add(item);
        }
      }
    } else {
      for (final exe in picked.value) {
        items.add((kind: SplitKind.app, value: exe));
      }
    }

    final existingGroup = groupKey.value.isEmpty || groupKey.value == _newGroup ? null : split.group(groupKey.value);
    // Путь группы: общий или, если пути разные, как у большинства её записей.
    final groupPlace = existingGroup == null ? null : _usual(split, existingGroup.items.items);
    final groupMixed = existingGroup != null && split.commonPlace(existingGroup.items.items) == null;
    final targetGroup = switch (groupKey.value) {
      '' => null,
      _newGroup => newName.text.trim().isEmpty ? null : newName.text.trim(),
      final g => g,
    };
    // «Как у группы»: её общий путь; у группы с разными путями — «Авто».
    final place = placeKey.value == _likeGroup ? (groupPlace ?? autoPlace) : _placeOfKey(placeKey.value);
    final pointless = place == autoPlace && targetGroup == null;
    final ready = items.isNotEmpty && !pointless && !(groupKey.value == _newGroup && targetGroup == null);

    final hint = switch (items.length) {
      0 when skipped.isEmpty => 'Сайт, IP, сеть или программа. Можно несколько — по одной на строку.',
      0 => 'Не понял: ${skipped.take(3).join(', ')}. Примеры: youtube.com, 10.0.0.0/8, steam.exe',
      1 => switch (items.single) {
        (kind: SplitKind.domain, :final value) => 'Сайт $value и все его поддомены',
        (kind: SplitKind.ip, :final value) => 'IP / сеть $value',
        (kind: SplitKind.app, :final value) => 'Программа $value',
      },
      final n =>
        '$n ${pluralRu(n, 'запись', 'записи', 'записей')}${skipped.isEmpty ? '' : '. Не понял: ${skipped.take(3).join(', ')}'}',
    };

    Future<void> pickExe() async {
      final files = await FilePicker.platform.pickFiles(
        dialogTitle: 'Программа для туннеля',
        type: FileType.custom,
        allowedExtensions: ['exe'],
        allowMultiple: true,
      );
      final names = [for (final f in files?.files ?? const <PlatformFile>[]) f.name];
      if (names.isEmpty) return;
      final before = text.text.trim();
      text.text = [if (before.isNotEmpty) before, ...names].join('\n');
    }

    void submit() {
      if (!ready) return;
      ref.read(splitTunnelProvider.notifier).addItems(items, place, group: targetGroup);
      Navigator.of(context).pop();
    }

    final what = currentTab.value == AddTab.type
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('add-text'),
                controller: text,
                autofocus: true,
                minLines: 1,
                maxLines: 5,
                decoration: const InputDecoration(hintText: 'steam.exe, youtube.com или 1.2.3.4'),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hint,
                      key: const ValueKey('add-hint'),
                      style: TextStyle(
                        fontSize: 12,
                        color: items.isEmpty && skipped.isNotEmpty ? RescueColors.warn : RescueColors.muted,
                      ),
                    ),
                  ),
                  TextButton(onPressed: pickExe, child: const Text('Файл .exe…')),
                ],
              ),
            ],
          )
        : _RunningList(running: running, split: split, query: query, picked: picked);

    final groupOptions = <(String, String)>[
      ('', 'Без группы'),
      for (final g in split.groups) (g.name, g.name),
      (_newGroup, '+ Новая…'),
    ];
    final several = servers != null && servers.several;
    final routeOptions = <(String, String)>[
      if (existingGroup != null)
        (
          _likeGroup,
          '${groupMixed ? 'Как у большинства в группе' : 'Как у группы'}: ${placeLabel(groupPlace, servers)}',
        ),
      ('auto', 'Авто'),
      ('bypass', 'Мимо VPN'),
      ('via', several ? 'VPN: любой сервер' : 'Через VPN'),
      if (several)
        for (final s in servers.servers) ('server:${s.tag}', s.fullName),
    ];

    return AlertDialog(
      title: const Text('Добавить'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: PillSegmented<AddTab>(
                  segments: const [
                    PillSegment(value: AddTab.type, label: 'Вписать'),
                    PillSegment(value: AddTab.running, label: 'Из запущенных'),
                  ],
                  value: currentTab.value,
                  onChanged: (t) => currentTab.value = t,
                  semanticLabel: 'Что добавить',
                  fontSize: 12,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 14),
              what,
              const SizedBox(height: 18),
              const Text('В ГРУППУ', style: RescueText.microLabel),
              const SizedBox(height: 8),
              FilterChips<String>(
                options: groupOptions,
                selected: groupKey.value,
                onSelected: (g) {
                  groupKey.value = g;
                  final hasPlace = g.isNotEmpty && g != _newGroup;
                  if (hasPlace && placeKey.value == 'auto') placeKey.value = _likeGroup;
                  if (!hasPlace && placeKey.value == _likeGroup) placeKey.value = 'auto';
                },
              ),
              if (groupKey.value == _newGroup) ...[
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('add-new-group'),
                  controller: newName,
                  autofocus: true,
                  maxLength: 40,
                  decoration: const InputDecoration(hintText: 'Название новой группы'),
                ),
              ],
              const SizedBox(height: 14),
              const Text('ПУТЬ', style: RescueText.microLabel),
              const SizedBox(height: 8),
              FilterChips<String>(
                options: routeOptions,
                selected: placeKey.value,
                onSelected: (k) => placeKey.value = k,
              ),
              if (pointless && items.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Без группы и с «Авто» запись ничего не изменит: выберите путь или группу.',
                  style: TextStyle(fontSize: 12, color: RescueColors.warn),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        FilledButton(
          key: const ValueKey('add-submit'),
          onPressed: ready ? submit : null,
          child: Text(items.length > 1 ? 'Добавить · ${items.length}' : 'Добавить'),
        ),
      ],
    );
  }
}

/// Самое частое место записей [items].
SplitPlace? _usual(SplitTunnel split, List<SplitRef> items) {
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

/// Запущенные программы с отметками; уже добавленные подписаны, где они сейчас.
class _RunningList extends StatelessWidget {
  const _RunningList({required this.running, required this.split, required this.query, required this.picked});

  final AsyncValue<List<RunningApp>> running;
  final SplitTunnel split;
  final ValueNotifier<String> query;
  final ValueNotifier<Set<String>> picked;

  @override
  Widget build(BuildContext context) {
    final q = query.value.toLowerCase();
    final apps = (running.valueOrNull ?? const <RunningApp>[])
        .where((a) => q.isEmpty || a.title.toLowerCase().contains(q) || a.exe.toLowerCase().contains(q))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Поиск'),
          onChanged: (v) => query.value = v,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 240,
          child: switch (running) {
            AsyncData() when apps.isEmpty => const Center(child: Text('Ничего не нашлось')),
            AsyncError() => const Center(child: Text('Не удалось получить список программ')),
            AsyncData() => ListView.builder(
              itemCount: apps.length,
              itemBuilder: (_, i) {
                final app = apps[i];
                final place = split.targetOf(SplitKind.app, app.exe);
                final group = split.groupOf(SplitKind.app, app.exe);
                final where = [
                  if (place != null) 'сейчас «${place.title}»',
                  if (group != null) 'в группе «$group»',
                ].join(', ');
                return CheckboxListTile(
                  dense: true,
                  value: picked.value.contains(app.exe),
                  title: Text(appTitle(app.exe, {app.exe.toLowerCase(): app.title})),
                  subtitle: Text(where.isEmpty ? app.exe : '${app.exe} · $where, перенесётся'),
                  onChanged: (v) =>
                      picked.value = v ?? false ? {...picked.value, app.exe} : ({...picked.value}..remove(app.exe)),
                );
              },
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }
}

/// Окно «Новая группа»: название и записи (из любых групп — перенесутся). Пути не меняются.
Future<void> showNewGroupDialog(
  BuildContext context, {
  required List<TunnelEntry> entries,
  Map<String, String> titles = const {},
}) => showDialog<void>(
  context: context,
  builder: (_) => _NewGroupDialog(entries: entries, titles: titles),
);

class _NewGroupDialog extends HookConsumerWidget {
  const _NewGroupDialog({required this.entries, required this.titles});

  final List<TunnelEntry> entries;
  final Map<String, String> titles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = useTextEditingController();
    useListenable(name);
    final query = useState('');
    final picked = useState(const <SplitRef>{});
    final q = query.value.toLowerCase();
    String title(TunnelEntry e) => e.kind == SplitKind.app ? appTitle(e.value, titles) : e.value;
    final listed = [
      ...entries.where((e) => e.group == null && (e.target != null)),
      ...entries.where((e) => e.group != null),
    ].where((e) => q.isEmpty || e.value.toLowerCase().contains(q) || title(e).toLowerCase().contains(q)).toList();
    final ready = name.text.trim().isNotEmpty && picked.value.isNotEmpty;

    return AlertDialog(
      title: const Text('Новая группа'),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('new-group-name'),
              controller: name,
              autofocus: true,
              maxLength: 40,
              decoration: const InputDecoration(hintText: 'Название, например «Работа и дом»'),
            ),
            const SizedBox(height: 8),
            const Text('ЧТО ПОЛОЖИТЬ', style: RescueText.microLabel),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('new-group-search'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Найти программу, сайт или IP',
              ),
              onChanged: (v) => query.value = v,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 260,
              child: listed.isEmpty
                  ? const Center(child: Text('Ничего не нашлось'))
                  : ListView.builder(
                      itemCount: listed.length,
                      itemBuilder: (_, i) {
                        final e = listed[i];
                        final ref0 = (kind: e.kind, value: e.value);
                        return CheckboxListTile(
                          key: ValueKey('new-group-pick-${e.value}'),
                          dense: true,
                          value: picked.value.contains(ref0),
                          title: Text(title(e)),
                          subtitle: Text(
                            e.group == null
                                ? '${e.value} · без группы'
                                : '${e.value} · сейчас в «${e.group}», перенесётся',
                          ),
                          onChanged: (v) =>
                              picked.value = v ?? false ? {...picked.value, ref0} : ({...picked.value}..remove(ref0)),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Пути записей не меняются — их можно поменять потом всей группе.',
              style: TextStyle(fontSize: 12, color: RescueColors.muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        FilledButton(
          key: const ValueKey('new-group-create'),
          onPressed: ready
              ? () {
                  ref.read(splitTunnelProvider.notifier).moveToGroup(name.text.trim(), picked.value);
                  Navigator.of(context).pop();
                }
              : null,
          child: Text(picked.value.isEmpty ? 'Создать' : 'Создать · ${picked.value.length}'),
        ),
      ],
    );
  }
}
