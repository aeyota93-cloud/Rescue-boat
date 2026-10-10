import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/common/pinned_scroll.dart';
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

/// Закладки над списком: все записи, только «мимо VPN», только «через VPN».
enum _Tab { all, bypass, via }

/// Ширина, с которой список показывается таблицей с колонками; уже — строки в две строчки.
const _wideFrom = 780.0;

/// Ширина колонки «Куда идёт» (переключатель «Авто / Мимо / VPN»).
const _routeWidth = 236.0;

/// Сколько строк показываем сразу, когда прокручивается вся страница; дальше — «Показать ещё».
const _compactRows = 30;

/// Шлюпка: «Раздельный туннель» в стиле «Д». Три положения у каждой записи: «Авто» (нет ни в
/// одном списке), «Мимо» и «VPN». Изменения действуют сразу, без переподключения.
///
/// Сверху закладки-«папки» «Все / Мимо / Через VPN» с поиском, ниже — тёмный список (deep):
/// первая строка жёлтая, игры и лаунчеры по умолчанию свёрнуты в одну строку с пунктирной рамкой.
/// Трафика по программам нет — только число соединений сейчас и ошибки за сутки.
///
/// Если области раздела хватает ([pinnedMinWidth] × [pinnedMinHeight]), шапка с кнопками, закладки
/// с поиском и заголовки колонок закреплены, а строки прокручиваются внутри тёмного списка.
/// Меньше — прокручивается вся страница, показаны первые [_compactRows] строк.
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
    final tab = useState(_Tab.all);
    final gamesOpen = useState(false);
    final limit = useState(_compactRows);

    final data = buildTunnelRows(split, connections, groups);
    final summary = data.summary;

    final header = RescuePageHeader(
      title: 'Раздельный туннель',
      actions: [
        OutlinedButton(onPressed: () => _pickRunning(context, ref), child: const Text('Из запущенных')),
        FilledButton(onPressed: () => _add(context, ref), child: const Text('+ Добавить сайт, IP или программу')),
        PopupMenuButton<void>(
          tooltip: 'Ещё',
          icon: const Icon(Icons.more_horiz_rounded),
          itemBuilder: (_) => [
            PopupMenuItem(onTap: () => _confirmReset(context, ref), child: const Text('Вернуть списки по умолчанию')),
          ],
        ),
      ],
    );
    final tabs = FolderTabs<_Tab>(
      semanticLabel: 'Списки',
      tabs: [
        FolderTab(value: _Tab.all, title: 'Все', badge: '${data.entries.length}'),
        FolderTab(value: _Tab.bypass, title: 'Мимо', badge: '${summary.bypass}'),
        FolderTab(value: _Tab.via, title: 'Через VPN', badge: '${summary.via}'),
      ],
      value: tab.value,
      onChanged: (t) => tab.value = t,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: _SearchRow(
        onChanged: (v) => query.value = v.trim().toLowerCase(),
        hint: switch (tab.value) {
          _Tab.all => 'Списки важнее общих правил и действуют сразу',
          _Tab.bypass => 'Идут напрямую, с домашнего IP',
          _Tab.via => 'Всегда через сервер, даже российские сайты',
        },
      ),
    );
    final notes = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '«Авто» — решают общие правила: российские сайты напрямую, остальное через VPN.',
          style: RescueText.caption,
        ),
        if (connections == null) ...[
          const SizedBox(height: 4),
          const Text('«Сейчас» появится, когда VPN подключён.', style: RescueText.caption),
        ],
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final pinned = isPinnedLayout(constraints);
          final list = _list(
            context,
            ref,
            data.entries,
            tab.value,
            query.value,
            gamesOpen,
            limit,
            wide: constraints.maxWidth >= _wideFrom,
            pinned: pinned,
          );
          if (pinned) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 20),
                  tabs,
                  const SizedBox(height: 20),
                  Expanded(child: list),
                  const SizedBox(height: 12),
                  notes,
                ],
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 20),
                tabs,
                const SizedBox(height: 20),
                list,
                const SizedBox(height: 12),
                notes,
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<TunnelEntry> all,
    _Tab tab,
    String query,
    ValueNotifier<bool> gamesOpen,
    ValueNotifier<int> limit, {
    required bool wide,
    required bool pinned,
  }) {
    final entries = all.where((e) {
      final byTab = switch (tab) {
        _Tab.all => true,
        _Tab.bypass => e.target == SplitTarget.bypass,
        _Tab.via => e.target == SplitTarget.via,
      };
      return byTab && (query.isEmpty || e.value.toLowerCase().contains(query));
    }).toList();

    // Игры по умолчанию, которые не в сети, сворачиваем в одну строку внизу (при поиске — не сворачиваем).
    final games = query.isEmpty
        ? entries.where((e) => e.isDefaultGame && e.target == SplitTarget.bypass && !e.online).toList()
        : const <TunnelEntry>[];
    final collapse = games.length >= 2;
    final plain = collapse ? entries.where((e) => !games.contains(e)).toList() : entries;

    // Прокручивается вся страница — длинный список обрезаем; в закреплённом режиме строит лениво.
    final shownPlain = pinned ? plain : plain.take(limit.value).toList();
    final rows = <Widget>[
      for (final (i, e) in shownPlain.indexed) _entryRow(context, ref, e, highlighted: i == 0, wide: wide),
      if (shownPlain.length < plain.length)
        _MoreRows(
          key: const ValueKey('tunnel-more'),
          shown: shownPlain.length,
          total: plain.length,
          onPressed: () => limit.value += _compactRows,
        ),
      if (collapse) ...[
        _gamesRow(ref, games, gamesOpen, wide: wide),
        if (gamesOpen.value)
          for (final g in games) _entryRow(context, ref, g, highlighted: false, wide: wide, indent: true),
      ],
    ];

    final empty = plain.isEmpty && !collapse;
    final emptyNote = Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        all.isEmpty ? 'Списки пусты. Добавьте программу, сайт или IP.' : 'Ничего не нашлось.',
        style: const TextStyle(fontSize: 13, color: RescueColors.subOnDeep),
        textAlign: TextAlign.center,
      ),
    );

    return DeepList(
      radius: 36,
      semanticLabel: 'Записи',
      children: [
        if (wide && !empty) const _HeaderRow(),
        if (empty)
          emptyNote
        else if (pinned)
          Expanded(
            child: PinnedList(
              key: const ValueKey('tunnel-rows'),
              itemCount: rows.length,
              spacing: 10,
              itemBuilder: (_, i) => rows[i],
            ),
          )
        else
          ...rows,
      ],
    );
  }

  Widget _gamesRow(WidgetRef ref, List<TunnelEntry> games, ValueNotifier<bool> open, {required bool wide}) {
    final errors = games.fold(0, (sum, g) => sum + g.errors);
    final values = [for (final g in games) g.value];
    return _TunnelRow(
      dashed: true,
      wide: wide,
      onTap: () => open.value = !open.value,
      semanticLabel: 'Игры и лаунчеры, ${games.length}, ${open.value ? 'свернуть' : 'раскрыть'}',
      icon: Icons.sports_esports_rounded,
      title: 'Игры и лаунчеры · ${games.length}',
      subtitle: open.value ? 'список по умолчанию · свернуть' : 'список по умолчанию · раскрыть',
      trailingIcon: open.value ? Icons.expand_less_rounded : Icons.expand_more_rounded,
      kind: 'Программы',
      connections: 0,
      errors: errors,
      route: (highlighted) => RouteSwitch(
        value: RouteChoice.bypass,
        semanticLabel: 'Куда идут игры и лаунчеры',
        width: wide ? _routeWidth : null,
        onAccent: highlighted,
        onChanged: (choice) {
          final notifier = ref.read(splitTunnelProvider.notifier);
          switch (choice) {
            case RouteChoice.auto:
              notifier.resetToDefault(SplitKind.app, values);
            case RouteChoice.vpn:
              notifier.addAll(SplitTarget.via, SplitKind.app, values);
            case RouteChoice.bypass:
              break;
          }
        },
      ),
    );
  }

  Widget _entryRow(
    BuildContext context,
    WidgetRef ref,
    TunnelEntry e, {
    required bool highlighted,
    required bool wide,
    bool indent = false,
  }) {
    final title = _title(e);
    final choice = switch (e.target) {
      null => RouteChoice.auto,
      SplitTarget.bypass => RouteChoice.bypass,
      SplitTarget.via => RouteChoice.vpn,
    };
    final row = _TunnelRow(
      wide: wide,
      highlighted: highlighted,
      // Программа в сети: по нажатию — куда она ходит, с переносом сайта или IP в списки.
      onTap: e.kind == SplitKind.app && e.online
          ? () => showDialog<void>(
              context: context,
              builder: (_) => _AppConnectionsDialog(exe: e.value),
            )
          : null,
      letter: e.kind == SplitKind.ip ? '#' : title.characters.first.toUpperCase(),
      title: title,
      subtitle: _detail(e),
      kind: switch (e.kind) {
        SplitKind.app => 'Программа',
        SplitKind.domain => 'Сайт',
        SplitKind.ip => 'IP и сеть',
      },
      connections: e.connections,
      errors: e.errors,
      route: (onAccent) => RouteSwitch(
        value: choice,
        semanticLabel: 'Куда идёт $title',
        width: wide ? _routeWidth : null,
        onAccent: onAccent,
        onChanged: (c) => _setRoute(ref, e.kind, e.value, c),
      ),
    );
    return indent ? Padding(padding: const EdgeInsets.only(left: 24), child: row) : row;
  }

  static void _setRoute(WidgetRef ref, SplitKind kind, String value, RouteChoice choice) {
    final notifier = ref.read(splitTunnelProvider.notifier);
    switch (choice) {
      case RouteChoice.auto:
        notifier.resetToDefault(kind, [value]);
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

// ---------- поиск и строки ----------

/// Поиск (таблетка цвета panel, высота 48) и подсказка к закладке справа.
class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.onChanged, required this.hint});

  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    const pill = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(999)), borderSide: BorderSide.none);
    final field = TextField(
      onChanged: onChanged,
      style: RescueText.body,
      decoration: const InputDecoration(
        filled: true,
        fillColor: RescueColors.panel,
        hintText: 'Найти программу, сайт или IP',
        prefixIcon: Icon(Icons.search_rounded, size: 18, color: RescueColors.muted),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: pill,
        enabledBorder: pill,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(999)),
          borderSide: BorderSide(color: RescueColors.accent, width: 1.5),
        ),
        semanticCounterText: '',
      ),
    );
    final note = Text(hint, style: RescueText.smallSecondary);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 560) {
          return Row(
            children: [
              Expanded(child: field),
              const SizedBox(width: 16),
              Flexible(child: note),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [field, const SizedBox(height: 10), note],
        );
      },
    );
  }
}

/// «Показать ещё» под обрезанным списком (прокрутка всей страницы).
class _MoreRows extends StatelessWidget {
  const _MoreRows({super.key, required this.shown, required this.total, required this.onPressed});

  final int shown;
  final int total;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      style: TextButton.styleFrom(foregroundColor: RescueColors.textOnDeep),
      onPressed: onPressed,
      child: Text('Показать ещё · $shown из $total'),
    ),
  );
}

/// Заголовки колонок тёмного списка (как в макете: 11 / 700 / 0.1em, subOnDeep).
class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
      color: RescueColors.subOnDeep,
    );
    return const ExcludeSemantics(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(
          children: [
            Expanded(flex: 22, child: Text('НАЗВАНИЕ', style: style)),
            SizedBox(width: 12),
            Expanded(flex: 10, child: Text('ТИП', style: style)),
            SizedBox(width: 12),
            Expanded(flex: 10, child: Text('СЕЙЧАС', style: style)),
            SizedBox(width: 12),
            Expanded(flex: 8, child: Text('ОШИБКИ', style: style)),
            SizedBox(width: 12),
            SizedBox(
              width: _routeWidth,
              child: Text('КУДА ИДЁТ', style: style),
            ),
          ],
        ),
      ),
    );
  }
}

/// Строка тёмного списка: на широком окне — колонки «Название · Тип · Сейчас · Ошибки · Куда идёт»,
/// на узком — название, под ним факты и переключатель во всю ширину.
/// [highlighted] — жёлтая строка, [dashed] — пунктирная рамка (свёрнутая группа игр).
class _TunnelRow extends StatelessWidget {
  const _TunnelRow({
    required this.wide,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.connections,
    required this.errors,
    required this.route,
    this.highlighted = false,
    this.dashed = false,
    this.onTap,
    this.letter,
    this.icon,
    this.trailingIcon,
    this.semanticLabel,
  });

  final bool wide;
  final String title;
  final String subtitle;
  final String kind;

  /// Соединений сейчас; null — неизвестно (VPN не подключён).
  final int? connections;

  /// Ошибок за сутки.
  final int errors;

  /// Переключатель «Авто / Мимо / VPN»; аргумент — стоит ли он на жёлтом.
  final Widget Function(bool onAccent) route;
  final bool highlighted;
  final bool dashed;
  final VoidCallback? onTap;
  final String? letter;
  final IconData? icon;
  final IconData? trailingIcon;
  final String? semanticLabel;

  String get _liveText => switch (connections) {
    null => '—',
    0 => 'не в сети',
    final n => '$n ${pluralRu(n, 'соединение', 'соединения', 'соединений')}',
  };

  @override
  Widget build(BuildContext context) {
    final c = DeepTileColors.of(highlighted: highlighted);
    final online = (connections ?? 0) > 0;
    final trailingIcon = this.trailingIcon;

    final tile = Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.tile, borderRadius: BorderRadius.circular(12)),
      child: icon != null
          ? Icon(icon, size: 18, color: c.foreground)
          : Text(
              letter ?? '',
              maxLines: 1,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.foreground),
            ),
    );
    final name = Row(
      children: [
        tile,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.title),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.subtitle),
              ),
            ],
          ),
        ),
        if (trailingIcon != null) ...[const SizedBox(width: 6), Icon(trailingIcon, size: 20, color: c.subtitle)],
      ],
    );
    final live = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: online ? (highlighted ? RescueColors.onAccent : RescueColors.accent) : RescueColors.off,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            _liveText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: c.foreground),
          ),
        ),
      ],
    );
    final kindText = Text(kind, maxLines: 1, style: TextStyle(fontSize: 13, color: c.subtitle));
    final errorsText = errors == 0 ? 'нет' : '$errors';

    final Widget content;
    if (wide) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Expanded(flex: 22, child: ExcludeSemantics(child: name)),
            const SizedBox(width: 12),
            Expanded(flex: 10, child: ExcludeSemantics(child: kindText)),
            const SizedBox(width: 12),
            Expanded(flex: 10, child: ExcludeSemantics(child: live)),
            const SizedBox(width: 12),
            Expanded(
              flex: 8,
              child: ExcludeSemantics(
                child: Text(
                  errorsText,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.foreground),
                ),
              ),
            ),
            const SizedBox(width: 12),
            route(highlighted),
          ],
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(child: name),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(left: 50),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    kindText,
                    live,
                    Text(
                      errors == 0 ? 'ошибок нет' : 'ошибок за сутки: $errors',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.foreground),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            route(highlighted),
          ],
        ),
      );
    }

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: dashed ? BorderSide.none : BorderSide(color: c.border),
    );
    final onTap = this.onTap;
    Widget row = Material(
      color: dashed ? Colors.transparent : c.background,
      shape: shape,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, customBorder: shape, excludeFromSemantics: true, child: content),
      ),
    );
    if (dashed) row = RescueCard.dashed(padding: EdgeInsets.zero, radius: 22, child: row);

    final spoken =
        semanticLabel ??
        [
          title,
          subtitle,
          kind,
          if (connections == null) 'сейчас неизвестно' else _liveText,
          if (errors == 0) 'ошибок нет' else '$errors ${pluralRu(errors, 'ошибка', 'ошибки', 'ошибок')} за сутки',
        ].join(', ');
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: onTap != null,
      label: spoken,
      hint: onTap != null && !dashed ? 'Показать, куда ходит программа' : null,
      onTap: onTap,
      child: row,
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
  RescueSegment(value: SplitTarget.bypass, label: 'Мимо VPN'),
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
              background: RescueColors.panel,
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
                      onChanged: (v) =>
                          selected.value = v ?? false ? {...selected.value, key} : ({...selected.value}..remove(key)),
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
              background: RescueColors.panel,
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
