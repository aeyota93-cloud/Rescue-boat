import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/insights/data/error_groups.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/insights/widget/insights_format.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: «Ошибки соединений» в стиле «Д» (макет docs/redesign/mockup/style-d-dark.html, экран
/// errors): период, сводка, тёмный список групп по сайтам и программам (выбранная — жёлтая) и
/// подробности выбранной группы (по часам, события, сырые строки ядра, кнопки туннеля).
///
/// Без бокового меню: каркас (RescueShell) подключается снаружи. Уже [wideFrom] список и
/// подробности идут друг под другом в одной прокрутке, шире — рядом; каждая колонка по высоте
/// содержимого и прокручивается сама, если не влезает.
class ErrorsPage extends HookConsumerWidget {
  const ErrorsPage({super.key, this.initialPeriod = InsightsPeriod.day});

  final InsightsPeriod initialPeriod;

  static const wideFrom = 860.0;

  /// Больше событий в подробностях не показываем: это для глаз, сырые строки — ниже.
  static const maxEvents = 100;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = useState(initialPeriod);
    final selectedKey = useState<String?>(null);
    final events = ref.watch(errorEventsProvider(period.value));
    final groupsValue = ref.watch(errorGroupsProvider(period.value));
    final groups = groupsValue.valueOrNull;
    final now = DateTime.now();

    ErrorGroup? selected;
    if (groups != null && groups.isNotEmpty) {
      selected = groups.firstWhere((g) => g.key == selectedKey.value, orElse: () => groups.first);
    }

    final header = SectionLabel.screen(
      'Ошибки соединений',
      trailing: PeriodSwitch<InsightsPeriod>(
        options: [for (final p in InsightsPeriod.values) (p, p.title)],
        value: period.value,
        onChanged: (p) => period.value = p,
      ),
    );
    final stats = _Stats(events: events.valueOrNull);

    final Widget? placeholder = switch (groups) {
      null when groupsValue.hasError => const _Placeholder('Не удалось прочитать журнал ошибок'),
      null => const _Placeholder('Читаем журнал ошибок…'),
      [] => _Placeholder('Ошибок нет ${periodPhrase(period.value)}'),
      _ => null,
    };

    return Material(
      color: RescueColors.panel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final group = selected;
          final top = [header, const SizedBox(height: 20), stats, const SizedBox(height: 20)];
          if (placeholder != null || group == null) {
            return SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...top, ?placeholder]),
            );
          }
          final list = _GroupList(groups: groups!, selected: group, onSelect: (g) => selectedKey.value = g.key);
          final details = _Details(key: ValueKey('details-${group.key}'), group: group, period: period.value, now: now);
          if (constraints.maxWidth < wideFrom) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...top, list, const SizedBox(height: 20), details],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...top,
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 10, child: _Hug(child: list)),
                    const SizedBox(width: 20),
                    Expanded(flex: 13, child: _Hug(child: details)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Колонка по высоте содержимого; если не влезает — своя прокрутка.
class _Hug extends StatelessWidget {
  const _Hug({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [Flexible(child: SingleChildScrollView(child: child))],
  );
}

/// Столбики для HourBars: за час — по 5 минут, за сутки — по часам (24), за неделю — по дням (7).
({List<int> counts, String title, String start, String end}) hourBuckets(
  List<ErrorEvent> events,
  InsightsPeriod period,
  DateTime now,
) {
  final DateTime start;
  final int n;
  final int Function(DateTime t) index;
  final String title;
  final String startLabel;
  final String endLabel;
  switch (period) {
    case InsightsPeriod.hour:
      n = 12;
      start = now.subtract(const Duration(hours: 1));
      index = (t) => t.difference(start).inMinutes ~/ 5;
      title = 'По 5 минут';
      startLabel = hhmm(start);
      endLabel = 'сейчас';
    case InsightsPeriod.day:
      n = 24;
      start = DateTime(now.year, now.month, now.day, now.hour).subtract(const Duration(hours: 23));
      index = (t) => t.difference(start).inMinutes ~/ 60;
      title = 'По часам';
      startLabel = '${sameDay(start, now) ? 'сегодня' : 'вчера'} ${start.hour.toString().padLeft(2, '0')}:00';
      endLabel = 'сейчас';
    case InsightsPeriod.week:
      n = 7;
      start = DateTime(now.year, now.month, now.day - 6);
      // По календарным дням; round — чтобы переход на летнее время не сдвигал день.
      index = (t) => (DateTime(t.year, t.month, t.day).difference(start).inHours / 24).round();
      title = 'По дням';
      startLabel = dayMonthShort(start);
      endLabel = 'сегодня';
  }
  final counts = List.filled(n, 0);
  for (final e in events) {
    if (e.kind == ErrorKind.suppressed) continue;
    counts[index(e.time).clamp(0, n - 1)] += e.count;
  }
  return (counts: counts, title: title, start: startLabel, end: endLabel);
}

/// Как пустить группу в туннель: сайт — правилом для домена, без сайта — правилом для программы.
({SplitKind kind, String value})? splitItemFor(ErrorGroup group) {
  final host = group.events.map((e) => e.host).firstWhere((h) => h.isNotEmpty, orElse: () => '');
  if (host.isNotEmpty) {
    final parsed = parseSplitItem(host);
    return (kind: SplitKind.domain, value: parsed?.kind == SplitKind.domain ? parsed!.value : host.toLowerCase());
  }
  if (group.app.isNotEmpty) return (kind: SplitKind.app, value: group.app);
  return null;
}

/// Сводка для владельца сервера: сайт, программа, путь, виды ошибок и время. Без IP-адресов.
String ownerSummary(ErrorGroup group, InsightsPeriod period, DateTime now) {
  final host = group.events.map((e) => e.host).firstWhere((h) => h.isNotEmpty, orElse: () => '');
  final kinds = <ErrorKind, int>{};
  for (final e in group.events) {
    kinds[e.kind] = (kinds[e.kind] ?? 0) + e.count;
  }
  final sortedKinds = kinds.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final offset = now.timeZoneOffset;
  final sign = offset.isNegative ? '−' : '+';
  final minutes = offset.inMinutes.abs() % 60;
  final zone = 'UTC$sign${offset.inHours.abs()}${minutes == 0 ? '' : ':${minutes.toString().padLeft(2, '0')}'}';
  const maxTimes = 20;
  final times = [for (final e in group.events.take(maxTimes)) '${dayMonthShort(e.time)} ${hhmmss(e.time)}'];
  final more = group.events.length - times.length;
  return [
    'Ошибки соединений ${periodPhrase(period)} (Шлюпка спасения)',
    if (host.isNotEmpty) 'Сайт: $host',
    'Программа: ${group.app.isEmpty ? 'неизвестна' : group.app}',
    'Путь: ${group.route.long}',
    'Всего: ${group.count} ${errorsWord(group.count)}',
    'Что случилось: ${sortedKinds.map((k) => '${k.key.title} — ${k.value}').join('; ')}',
    'Когда ($zone): ${times.join(', ')}${more > 0 ? ' и ещё $more' : ''}',
  ].join('\n');
}

class _Stats extends StatelessWidget {
  const _Stats({required this.events});

  /// null — ещё читаются.
  final List<ErrorEvent>? events;

  @override
  Widget build(BuildContext context) {
    final list = events;
    String count(bool Function(ErrorEvent e) test) {
      if (list == null) return '—';
      return '${countErrors(list.where((e) => e.kind != ErrorKind.suppressed && test(e)))}';
    }

    return RescueCard(
      semanticLabel: 'Сводка',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatColumns(
            columns: [
              StatColumn(label: 'ВСЕГО ОШИБОК', value: list == null ? '—' : '${countErrors(list)}'),
              StatColumn(
                label: 'ЧЕРЕЗ VPN',
                value: count((e) => e.route == ErrorRoute.vpn),
                lineColor: RescueColors.accent,
              ),
              StatColumn(label: 'МИМО VPN', value: count((e) => e.route == ErrorRoute.direct)),
              StatColumn(
                label: 'ЗАМИРАНИЯ СВЯЗИ',
                value: count((e) => e.kind == ErrorKind.stall),
                lineColor: RescueColors.warn,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Что не смогло подключиться. Хранится только на этом компьютере, 7 дней.',
            style: RescueText.caption,
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => RescueCard.dashed(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(text, style: RescueText.body, textAlign: TextAlign.center),
    ),
  );
}

/// Тёмный список групп: выбранная строка жёлтая, справа — кольцо с числом ошибок.
class _GroupList extends StatelessWidget {
  const _GroupList({required this.groups, required this.selected, required this.onSelect});

  final List<ErrorGroup> groups;
  final ErrorGroup selected;
  final ValueChanged<ErrorGroup> onSelect;

  @override
  Widget build(BuildContext context) {
    final most = groups.fold<int>(1, (m, g) => g.count > m ? g.count : m);
    return DeepList(
      title: 'По сайтам и программам',
      count: '${groups.length}',
      semanticLabel: 'Список',
      radius: 36,
      children: [for (final g in groups) _tile(g, most)],
    );
  }

  Widget _tile(ErrorGroup g, int most) {
    final on = g.key == selected.key;
    final c = DeepTileColors.of(highlighted: on);
    final sub = groupSubtitle(g);
    return DeepListTile(
      leading: tileLetter(g.target),
      title: g.target,
      subtitle: sub,
      highlighted: on,
      minHeight: 68,
      tileSize: 38,
      radius: 22,
      semanticLabel: '${g.target}, $sub, ${g.count} ${errorsWord(g.count)}',
      onTap: () => onSelect(g),
      trailing: ExcludeSemantics(
        child: RingStat(
          value: g.count / most,
          label: '${g.count}',
          size: 40,
          strokeWidth: 3.5,
          color: c.ring,
          trackColor: c.ringTrack,
          labelColor: c.foreground,
        ),
      ),
    );
  }
}

/// Подробности выбранной группы: закладка с названием, по часам, события, сырые строки, кнопки.
class _Details extends StatelessWidget {
  const _Details({super.key, required this.group, required this.period, required this.now});

  final ErrorGroup group;
  final InsightsPeriod period;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final bars = hourBuckets(group.events, period, now);
    final appText = group.app.isEmpty ? 'программа неизвестна' : group.app;
    final routeText = group.route == ErrorRoute.block ? 'заблокировано' : 'идёт ${group.route.long}';
    final withDate = period == InsightsPeriod.week;
    final shown = group.events.take(ErrorsPage.maxEvents).toList();
    final total = bars.counts.fold<int>(0, (s, v) => s + v);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Подробности',
      child: FolderTabs<String>(
        tabs: [FolderTab(value: group.key, title: group.target)],
        value: group.key,
        onChanged: null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$appText · $routeText · ${group.count} ${errorsWord(group.count)} ${periodPhrase(period)}',
              style: RescueText.smallSecondary,
            ),
            const SizedBox(height: 16),
            HourBars(
              key: const ValueKey('errors-hour-bars'),
              counts: bars.counts,
              title: bars.title.toUpperCase(),
              startLabel: bars.start,
              endLabel: bars.end,
              height: 70,
              semanticLabel: 'Ошибки ${bars.title.toLowerCase()}: всего $total',
            ),
            const SizedBox(height: 12),
            for (final e in shown) _EventRow(event: e, now: now, withDate: withDate),
            if (group.events.length > shown.length) ...[
              const SizedBox(height: 8),
              Text('Показаны последние ${shown.length} из ${group.events.length}', style: RescueText.caption),
            ],
            const SizedBox(height: 16),
            _RawLines(key: ValueKey('raw-${group.key}'), events: group.events),
            const SizedBox(height: 16),
            _Actions(group: group, period: period),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.now, required this.withDate});

  final ErrorEvent event;
  final DateTime now;
  final bool withDate;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final address = e.ip.isNotEmpty ? '${e.ip}:${e.port}' : (e.host.isNotEmpty ? e.host : '—');
    return Container(
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: RescueColors.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: withDate ? 100 : 56,
            child: Text(
              withDate ? eventTime(e.time, now) : hhmm(e.time),
              style: monoStyle.copyWith(fontSize: 13),
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(eventWhat(e), style: RescueText.small, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(address, style: RescueText.smallSecondary, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// «Сырые строки»: исходный текст ошибок ядра, свёрнуто по умолчанию.
class _RawLines extends HookWidget {
  const _RawLines({super.key, required this.events});

  final List<ErrorEvent> events;

  /// Больше не нужно: это для глаз, а не для выгрузки.
  static const _max = 200;

  @override
  Widget build(BuildContext context) {
    final open = useState(false);
    final radius = BorderRadius.circular(20);
    return Container(
      decoration: BoxDecoration(color: RescueColors.deep, borderRadius: radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open.value,
            child: InkWell(
              borderRadius: radius,
              onTap: () => open.value = !open.value,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(
                        open.value ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                        size: 18,
                        color: RescueColors.subOnDeep,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Сырые строки',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: RescueColors.subOnDeep),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (open.value)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: SelectableText(
                [
                  for (final e in events.take(_max)) _line(e),
                  if (events.length > _max) '… и ещё ${events.length - _max}',
                ].join('\n'),
                style: monoStyle.copyWith(height: 1.6),
              ),
            ),
        ],
      ),
    );
  }

  static String _line(ErrorEvent e) {
    final where = [
      if (e.app.isNotEmpty) '[${e.app}]',
      if (e.target.isNotEmpty) e.host.isNotEmpty && e.port > 0 ? '${e.host}:${e.port}' : e.target,
      e.route.long,
    ].join(' ');
    final n = e.count > 1 ? ' (×${e.count})' : '';
    return '${hhmmss(e.time)} ${e.kind.name} $where: ${e.message.isEmpty ? e.kind.title : e.message}$n';
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.group, required this.period});

  final ErrorGroup group;
  final InsightsPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = splitItemFor(group);
    final current = item == null ? null : ref.watch(splitTunnelProvider).targetOf(item.kind, item.value);

    VoidCallback? add(SplitTarget target) => item == null || current == target
        ? null
        : () {
            ref.read(splitTunnelProvider.notifier).add(target, item.kind, item.value);
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(SnackBar(content: Text('Добавлено в «${target.title}»: ${item.value}')));
          };

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: add(SplitTarget.bypass),
          child: Text(current == SplitTarget.bypass ? 'Уже мимо VPN' : 'Пустить мимо VPN'),
        ),
        OutlinedButton(
          onPressed: add(SplitTarget.via),
          child: Text(current == SplitTarget.via ? 'Уже через VPN' : 'Всегда через VPN'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: RescueColors.text),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: ownerSummary(group, period, DateTime.now())));
            if (!context.mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('Скопировано: сайт, программа, путь, виды ошибок и время, без IP')),
            );
          },
          child: const Text(
            'Скопировать для владельца сервера',
            style: TextStyle(decoration: TextDecoration.underline, decorationColor: RescueColors.text),
          ),
        ),
      ],
    );
  }
}
