import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/common/rescue_page_header.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/data/running_apps.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/model/tunnel_rows.dart';
import 'package:hiddify/features/split_tunnel/notifier/live_connections_notifier.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum _Filter { all, apps, sites, ips }

/// Шлюпка: «Раздельный туннель» — таблица (Tunnel.dc.html). Три положения у каждой записи:
/// «Авто» (нет ни в одном списке), «Мимо» и «VPN». Изменения действуют сразу, без переподключения.
class SplitTunnelTablePage extends HookConsumerWidget {
  const SplitTunnelTablePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitTunnelProvider);
    // Соединения опрашиваем, только пока страница видна (скрытая ветка навигации — TickerMode выключен).
    final visible = TickerMode.of(context);
    final connections = visible ? ref.watch(liveConnectionsProvider).valueOrNull : null;
    final groups = ref.watch(errorGroupsProvider(InsightsPeriod.day)).valueOrNull ?? const <ErrorGroup>[];
    final query = useState('');
    final filter = useState(_Filter.all);
    final gamesOpen = useState(false);

    final data = buildTunnelRows(split, connections, groups);
    final summary = data.summary;
    String count(int? n) => n == null ? '—' : '$n';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RescuePageHeader(
              title: 'Раздельный туннель',
              subtitle: 'Эти правила важнее общих и действуют сразу',
              actions: [
                OutlinedButton(onPressed: () => _pickRunning(context, ref), child: const Text('Из запущенных')),
                FilledButton(onPressed: () => _add(context, ref), child: const Text('+ Добавить')),
                PopupMenuButton<void>(
                  tooltip: 'Ещё',
                  icon: const Icon(Icons.more_horiz_rounded),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      onTap: () => _confirmReset(context, ref),
                      child: const Text('Вернуть списки по умолчанию'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            RescueGrid(
              children: [
                StatTile(label: 'Через VPN', value: '${summary.via}', markerColor: RescueColors.accent),
                StatTile(label: 'Мимо VPN', value: '${summary.bypass}', markerColor: RescueColors.teal),
                StatTile(label: 'По общим правилам', value: count(summary.auto), markerColor: RescueColors.fair),
                StatTile(label: 'Сейчас в сети', value: count(summary.online), markerColor: RescueColors.good),
              ],
            ),
            const SizedBox(height: 16),
            RescueCard(
              semanticLabel: 'Правила',
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 220, maxWidth: 420),
                        child: TextField(
                          onChanged: (v) => query.value = v.trim().toLowerCase(),
                          style: RescueText.body,
                          decoration: const InputDecoration(
                            isDense: true,
                            prefixIcon: Icon(Icons.search_rounded, size: 20, color: RescueColors.textSecondary),
                            hintText: 'Найти программу, сайт или IP',
                            semanticCounterText: '',
                          ),
                        ),
                      ),
                      FilterChips<_Filter>(
                        options: const [
                          (_Filter.all, 'Всё'),
                          (_Filter.apps, 'Программы'),
                          (_Filter.sites, 'Сайты'),
                          (_Filter.ips, 'IP'),
                        ],
                        selected: filter.value,
                        onSelected: (f) => filter.value = f,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _table(context, ref, data.entries, filter.value, query.value, gamesOpen),
                  const SizedBox(height: 12),
                  const Text(
                    '«Авто» — решают общие правила: российские сайты напрямую, остальное через VPN.',
                    style: RescueText.caption,
                  ),
                  if (connections == null) ...[
                    const SizedBox(height: 4),
                    const Text(
                      '«Сейчас» появится, когда VPN подключён.',
                      style: RescueText.caption,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table(
    BuildContext context,
    WidgetRef ref,
    List<TunnelEntry> all,
    _Filter filter,
    String query,
    ValueNotifier<bool> gamesOpen,
  ) {
    final entries = all.where((e) {
      final byKind = switch (filter) {
        _Filter.all => true,
        _Filter.apps => e.kind == SplitKind.app,
        _Filter.sites => e.kind == SplitKind.domain,
        _Filter.ips => e.kind == SplitKind.ip,
      };
      return byKind && (query.isEmpty || e.value.toLowerCase().contains(query));
    }).toList();

    // Игры по умолчанию, которые не в сети, сворачиваем в одну строку (при поиске — не сворачиваем).
    final games = query.isEmpty
        ? entries.where((e) => e.isDefaultGame && e.target == SplitTarget.bypass && !e.online).toList()
        : const <TunnelEntry>[];
    final collapse = games.length >= 2;

    final rows = <RescueTableRow>[];
    var groupAdded = false;
    for (final e in entries) {
      if (collapse && games.contains(e)) {
        if (!groupAdded) {
          groupAdded = true;
          rows.add(_gamesRow(ref, games, gamesOpen));
          if (gamesOpen.value) rows.addAll(games.map((g) => _entryRow(context, ref, g, indent: true)));
        }
        continue;
      }
      rows.add(_entryRow(context, ref, e));
    }

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          all.isEmpty ? 'Списки пусты. Добавьте программу, сайт или IP.' : 'Ничего не нашлось.',
          style: RescueText.smallSecondary,
          textAlign: TextAlign.center,
        ),
      );
    }

    return RescueTable(
      minWidth: 820,
      rowHeight: 60,
      columns: const [
        RescueColumn('Название', flex: 2.4),
        RescueColumn('Тип'),
        RescueColumn('Куда идёт', width: 230),
        RescueColumn('Сейчас', flex: 1.4),
        RescueColumn('Ошибки за сутки', alignEnd: true),
      ],
      rows: rows,
    );
  }

  RescueTableRow _gamesRow(WidgetRef ref, List<TunnelEntry> games, ValueNotifier<bool> open) {
    final errors = games.fold(0, (sum, g) => sum + g.errors);
    final values = [for (final g in games) g.value];
    return RescueTableRow(
      onTap: () => open.value = !open.value,
      cells: [
        _NameCell(
          title: 'Игры и лаунчеры (${games.length})',
          detail: open.value ? 'список по умолчанию · свернуть' : 'список по умолчанию · раскрыть',
          leading: const Icon(Icons.sports_esports_rounded, size: 18, color: Colors.white),
          tint: const Color(0xFF1B2838),
          trailing: Icon(
            open.value ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 20,
            color: RescueColors.textSecondary,
          ),
        ),
        const _KindText('Программы'),
        RouteSwitch(
          value: RouteChoice.bypass,
          semanticLabel: 'Куда идут игры и лаунчеры',
          onChanged: (choice) {
            final notifier = ref.read(splitTunnelProvider.notifier);
            switch (choice) {
              case RouteChoice.auto:
                notifier.removeEverywhere(SplitKind.app, values);
              case RouteChoice.vpn:
                notifier.addAll(SplitTarget.via, SplitKind.app, values);
              case RouteChoice.bypass:
                break;
            }
          },
        ),
        const _LiveCell(connections: 0),
        _ErrorsCell(errors),
      ],
    );
  }

  RescueTableRow _entryRow(BuildContext context, WidgetRef ref, TunnelEntry e, {bool indent = false}) {
    final title = _title(e);
    final choice = switch (e.target) {
      null => RouteChoice.auto,
      SplitTarget.bypass => RouteChoice.bypass,
      SplitTarget.via => RouteChoice.vpn,
    };
    return RescueTableRow(
      // Программа в сети: по нажатию — куда она ходит, с переносом сайта или IP в списки.
      onTap: e.kind == SplitKind.app && e.online
          ? () => showDialog<void>(context: context, builder: (_) => _AppConnectionsDialog(exe: e.value))
          : null,
      cells: [
        Padding(
          padding: EdgeInsets.only(left: indent ? 24 : 0),
          child: _NameCell(
            title: title,
            detail: _detail(e),
            letter: e.kind == SplitKind.ip ? '#' : title.characters.first.toUpperCase(),
            tint: e.kind == SplitKind.ip ? RescueColors.muted : _tint(e.value),
          ),
        ),
        _KindText(switch (e.kind) {
          SplitKind.app => 'Программа',
          SplitKind.domain => 'Сайт',
          SplitKind.ip => 'IP / сеть',
        }),
        RouteSwitch(
          value: choice,
          semanticLabel: 'Куда идёт $title',
          onChanged: (c) => _setRoute(ref, e.kind, e.value, c),
        ),
        _LiveCell(connections: e.connections),
        _ErrorsCell(e.errors),
      ],
    );
  }

  static void _setRoute(WidgetRef ref, SplitKind kind, String value, RouteChoice choice) {
    final notifier = ref.read(splitTunnelProvider.notifier);
    switch (choice) {
      case RouteChoice.auto:
        notifier.removeEverywhere(kind, [value]);
      case RouteChoice.bypass:
        notifier.add(SplitTarget.bypass, kind, value);
      case RouteChoice.vpn:
        notifier.add(SplitTarget.via, kind, value);
    }
  }

  static String _title(TunnelEntry e) =>
      e.kind == SplitKind.app ? e.value.replaceFirst(RegExp(r'\.exe$', caseSensitive: false), '') : e.value;

  static String _detail(TunnelEntry e) => switch (e.kind) {
    SplitKind.app => e.isDefaultGame ? '${e.value} · из списка игр' : e.value,
    SplitKind.domain => 'и все поддомены',
    SplitKind.ip when isHomeNetwork(e.value) => 'домашняя сеть',
    SplitKind.ip when e.value.endsWith('/32') || e.value.endsWith('/128') => 'один адрес',
    SplitKind.ip => 'сеть',
  };

  static const _tints = [
    Color(0xFF2F6FD6),
    Color(0xFF1F8BC4),
    Color(0xFFB5562F),
    Color(0xFF5865F2),
    Color(0xFF2E7D5B),
    Color(0xFFC27C1A),
    Color(0xFFC9372C),
    Color(0xFFE0661B),
  ];

  // Цвет значка постоянный для имени (не меняется между запусками).
  static Color _tint(String value) {
    var h = 0;
    for (final c in value.toLowerCase().codeUnits) {
      h = (h * 31 + c) & 0x7FFFFFFF;
    }
    return _tints[h % _tints.length];
  }

  // ---------- добавление ----------

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_AddResult>(context: context, builder: (_) => const _AddDialog());
    if (result == null || !context.mounted) return;
    final notifier = ref.read(splitTunnelProvider.notifier);
    switch (result.action) {
      case _AddAction.item:
        final item = result.item!;
        notifier.add(result.target, item.kind, item.value);
      case _AddAction.exe:
        final picked = await FilePicker.platform.pickFiles(
          dialogTitle: 'Программа для списка «${result.target.title}»',
          type: FileType.custom,
          allowedExtensions: ['exe'],
          allowMultiple: true,
        );
        final names = [for (final f in picked?.files ?? const <PlatformFile>[]) f.name];
        if (names.isNotEmpty) notifier.addAll(result.target, SplitKind.app, names);
      case _AddAction.list:
        if (context.mounted) await _pasteMany(context, ref, result.target);
    }
  }

  Future<void> _pasteMany(BuildContext context, WidgetRef ref, SplitTarget target) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Добавить в «${target.title}»'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: 'По одному на строку:\nyoutube.com\nhttps://example.com/page\n8.8.8.8\n10.0.0.0/8\ngame.exe',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Добавить')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;
    final result = ref.read(splitTunnelProvider.notifier).addMany(target, text);
    if (!context.mounted) return;
    final skipped = result.skipped.isEmpty ? '' : '. Не понял: ${result.skipped.take(5).join(', ')}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Добавлено: ${result.added}$skipped')));
  }

  Future<void> _pickRunning(BuildContext context, WidgetRef ref) async {
    final picked = await showDialog<({SplitTarget target, List<String> exes})>(
      context: context,
      builder: (_) => const _RunningAppsDialog(),
    );
    if (picked == null || picked.exes.isEmpty) return;
    ref.read(splitTunnelProvider.notifier).addAll(picked.target, SplitKind.app, picked.exes);
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Вернуть списки по умолчанию?'),
        content: const Text('Оба списка очистятся, в «Мимо VPN» вернутся игры и лаунчеры.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Вернуть')),
        ],
      ),
    );
    if (ok ?? false) ref.read(splitTunnelProvider.notifier).resetToDefaults();
  }
}

// ---------- ячейки ----------

class _NameCell extends StatelessWidget {
  const _NameCell({required this.title, required this.detail, required this.tint, this.letter, this.leading, this.trailing});

  final String title;
  final String detail;
  final Color tint;
  final String? letter;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return Row(
      children: [
        ExcludeSemantics(
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)),
            child:
                leading ??
                Text(
                  letter ?? '',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: RescueColors.text),
              ),
              Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: RescueText.caption),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 6), trailing],
      ],
    );
  }
}

class _KindText extends StatelessWidget {
  const _KindText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 13, color: RescueColors.textTertiary));
}

class _LiveCell extends StatelessWidget {
  const _LiveCell({required this.connections});

  /// null — неизвестно (VPN не подключён).
  final int? connections;

  @override
  Widget build(BuildContext context) {
    final n = connections;
    final online = (n ?? 0) > 0;
    final text = switch (n) {
      null => '—',
      0 => 'не в сети',
      _ => '$n ${pluralRu(n, 'соединение', 'соединения', 'соединений')}',
    };
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: online ? RescueColors.good : RescueColors.muted, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            semanticsLabel: n == null ? 'неизвестно' : null,
            style: TextStyle(fontSize: 13, color: online ? RescueColors.text : RescueColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _ErrorsCell extends StatelessWidget {
  const _ErrorsCell(this.errors);

  final int errors;

  @override
  Widget build(BuildContext context) {
    if (errors == 0) {
      return const Text('нет', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: RescueColors.textSecondary));
    }
    return RescueBadge.tag(
      label: '$errors',
      kind: errors > 3 ? RescueBadgeKind.important : RescueBadgeKind.warning,
      semanticLabel: '$errors ${pluralRu(errors, 'ошибка', 'ошибки', 'ошибок')} за сутки',
    );
  }
}

// ---------- диалоги ----------

enum _AddAction { item, exe, list }

class _AddResult {
  const _AddResult(this.action, this.target, [this.item]);

  final _AddAction action;
  final SplitTarget target;
  final ({SplitKind kind, String value})? item;
}

/// Сегменты «Мимо VPN / Через VPN» для диалогов добавления.
const _targetSegments = [
  RescueSegment(
    value: SplitTarget.bypass,
    label: 'Мимо VPN',
    selectedBackground: RescueColors.bypassBg,
    selectedForeground: RescueColors.bypassText,
  ),
  RescueSegment(value: SplitTarget.via, label: 'Через VPN'),
];

class _AddDialog extends HookWidget {
  const _AddDialog();

  @override
  Widget build(BuildContext context) {
    final text = useState('');
    final target = useState(SplitTarget.bypass);
    final item = parseSplitItem(text.value);
    final hint = switch (item) {
      _ when text.value.trim().isEmpty => 'Можно вставить ссылку, домен, IP, сеть или путь к .exe',
      null => 'Не понял. Примеры: youtube.com, 10.0.0.0/8, steam.exe',
      (kind: SplitKind.domain, :final value) => 'Сайт $value и все поддомены',
      (kind: SplitKind.ip, :final value) => 'IP / сеть $value',
      (kind: SplitKind.app, :final value) => 'Программа $value',
    };
    void submit() {
      if (item != null) Navigator.pop(context, _AddResult(_AddAction.item, target.value, item));
    }

    return AlertDialog(
      title: const Text('Добавить правило'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => text.value = v,
              onSubmitted: (_) => submit(),
              decoration: const InputDecoration(hintText: 'Сайт, IP или программа'),
            ),
            const SizedBox(height: 6),
            Text(hint, style: RescueText.caption),
            const SizedBox(height: 16),
            const Text('Куда направить', style: RescueText.smallSecondary),
            const SizedBox(height: 6),
            RescueSegmented<SplitTarget>(
              segments: _targetSegments,
              value: target.value,
              onChanged: (t) => target.value = t,
              semanticLabel: 'Куда направить',
              expand: true,
              background: RescueColors.background,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, _AddResult(_AddAction.exe, target.value)),
                  child: const Text('Файл .exe…'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, _AddResult(_AddAction.list, target.value)),
                  child: const Text('Вставить списком…'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: item == null ? null : submit, child: const Text('Добавить')),
      ],
    );
  }
}

class _RunningAppsDialog extends HookConsumerWidget {
  const _RunningAppsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = useFuture(useMemoized(listRunningApps));
    final split = ref.watch(splitTunnelProvider);
    final query = useState('');
    final target = useState(SplitTarget.bypass);
    final selected = useState(<String>{});
    final q = query.value.toLowerCase();
    final filtered = (apps.data ?? const <RunningApp>[])
        .where((a) => q.isEmpty || a.title.toLowerCase().contains(q) || a.exe.toLowerCase().contains(q))
        .toList();
    return AlertDialog(
      title: const Text('Из запущенных программ'),
      content: SizedBox(
        width: 520,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Поиск'),
              onChanged: (v) => query.value = v,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: switch (apps.connectionState) {
                ConnectionState.done when filtered.isEmpty => const Center(child: Text('Ничего не нашлось')),
                ConnectionState.done => ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final app = filtered[i];
                    final key = app.exe.toLowerCase();
                    final inList = split.targetOf(SplitKind.app, app.exe);
                    return CheckboxListTile(
                      dense: true,
                      value: selected.value.contains(key),
                      title: Text(app.title),
                      subtitle: Text(inList == null ? app.exe : '${app.exe} · сейчас «${inList.title}»'),
                      onChanged: (v) => selected.value = v ?? false
                          ? {...selected.value, key}
                          : ({...selected.value}..remove(key)),
                    );
                  },
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
            const SizedBox(height: 8),
            RescueSegmented<SplitTarget>(
              segments: _targetSegments,
              value: target.value,
              onChanged: (t) => target.value = t,
              semanticLabel: 'Куда направить',
              expand: true,
              background: RescueColors.background,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: selected.value.isEmpty
              ? null
              : () => Navigator.pop(context, (
                  target: target.value,
                  exes: [
                    for (final a in apps.data ?? const <RunningApp>[])
                      if (selected.value.contains(a.exe.toLowerCase())) a.exe,
                  ],
                )),
          child: Text('Добавить (${selected.value.length})'),
        ),
      ],
    );
  }
}

/// Куда сейчас ходит программа: сайт или IP можно сразу отправить мимо VPN или через VPN.
class _AppConnectionsDialog extends ConsumerWidget {
  const _AppConnectionsDialog({required this.exe});

  final String exe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(liveConnectionsProvider).valueOrNull ?? const <NetConnection>[];
    final notifier = ref.read(splitTunnelProvider.notifier);
    final hosts = <String, NetConnection>{};
    for (final c in all.where((c) => c.exe.toLowerCase() == exe.toLowerCase())) {
      hosts.putIfAbsent(c.host.isNotEmpty ? c.host : c.ip, () => c);
    }
    return AlertDialog(
      title: Text('Куда ходит $exe'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: hosts.isEmpty
            ? const Center(child: Text('Сейчас соединений нет', style: RescueText.smallSecondary))
            : ListView(
                children: [
                  for (final MapEntry(key: name, value: c) in hosts.entries)
                    ListTile(
                      dense: true,
                      title: Text(name),
                      subtitle: Text('${c.viaVpn ? 'через VPN' : 'напрямую'} · ${c.network}:${c.port}'),
                      trailing: PopupMenuButton<VoidCallback>(
                        tooltip: 'В список',
                        onSelected: (action) => action(),
                        itemBuilder: (_) => [
                          if (c.host.isNotEmpty) ...[
                            PopupMenuItem(
                              value: () => notifier.add(SplitTarget.bypass, SplitKind.domain, siteOf(c.host)),
                              child: Text('Сайт ${siteOf(c.host)} → мимо VPN'),
                            ),
                            PopupMenuItem(
                              value: () => notifier.add(SplitTarget.via, SplitKind.domain, siteOf(c.host)),
                              child: Text('Сайт ${siteOf(c.host)} → через VPN'),
                            ),
                          ],
                          if (c.ip.isNotEmpty) ...[
                            PopupMenuItem(
                              value: () => notifier.add(SplitTarget.bypass, SplitKind.ip, cidrOf(c.ip)),
                              child: Text('IP ${c.ip} → мимо VPN'),
                            ),
                            PopupMenuItem(
                              value: () => notifier.add(SplitTarget.via, SplitKind.ip, cidrOf(c.ip)),
                              child: Text('IP ${c.ip} → через VPN'),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))],
    );
  }
}
