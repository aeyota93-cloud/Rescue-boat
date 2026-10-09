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

/// Шлюпка: «Ошибки соединений» — счётчики за период, группы по сайтам и программам и подробности
/// выбранной группы (по часам, список событий, сырые строки ядра, кнопки туннеля).
///
/// Без бокового меню: каркас (RescueShell) подключается снаружи. Уже 900 px список и подробности
/// идут друг под другом в одной прокрутке, шире — рядом, каждая панель прокручивается сама.
class ErrorsPage extends HookConsumerWidget {
  const ErrorsPage({super.key, this.initialPeriod = InsightsPeriod.day});

  final InsightsPeriod initialPeriod;

  static const wideFrom = 900.0;

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
    void select(ErrorGroup g) => selectedKey.value = g.key;

    final header = _Header(period: period.value, onChanged: (p) => period.value = p);
    final stats = _Stats(events: events.valueOrNull);

    final Widget? placeholder = switch (groups) {
      null when groupsValue.hasError => const _Placeholder('Не удалось прочитать журнал ошибок'),
      null => const _Placeholder('Читаем журнал ошибок…'),
      [] => _Placeholder('Ошибок нет ${periodPhrase(period.value)}'),
      _ => null,
    };

    return Material(
      color: RescueColors.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= wideFrom;
          final group = selected;
          if (placeholder != null || group == null || !wide) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: header),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                SliverToBoxAdapter(child: stats),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                if (placeholder != null || group == null)
                  SliverToBoxAdapter(child: placeholder)
                else ...[
                  _cardSliver(
                    padding: const EdgeInsets.all(16),
                    slivers: [
                      const SliverToBoxAdapter(child: _GroupsTitle()),
                      SliverList.builder(
                        itemCount: groups!.length,
                        itemBuilder: (context, i) => _GroupTile(
                          group: groups[i],
                          selected: groups[i].key == group.key,
                          now: now,
                          onTap: () => select(groups[i]),
                        ),
                      ),
                    ],
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  _cardSliver(padding: const EdgeInsets.all(20), slivers: _detailsSlivers(group, period.value, now)),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 16),
                stats,
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 10,
                        child: RescueCard(
                          semanticLabel: 'Список',
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _GroupsTitle(),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: groups!.length,
                                  itemBuilder: (context, i) => _GroupTile(
                                    group: groups[i],
                                    selected: groups[i].key == group.key,
                                    now: now,
                                    onTap: () => select(groups[i]),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 13,
                        child: RescueCard(
                          semanticLabel: 'Подробности',
                          padding: EdgeInsets.zero,
                          child: CustomScrollView(
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.all(20),
                                sliver: SliverMainAxisGroup(slivers: _detailsSlivers(group, period.value, now)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Карточка вокруг ленивого списка (на узком окне всё в одной прокрутке).
  static Widget _cardSliver({required EdgeInsets padding, required List<Widget> slivers}) => DecoratedSliver(
    decoration: BoxDecoration(
      color: RescueColors.card,
      border: Border.all(color: RescueColors.line),
      borderRadius: BorderRadius.circular(20),
    ),
    sliver: SliverPadding(
      padding: padding,
      sliver: SliverMainAxisGroup(slivers: slivers),
    ),
  );

  static List<Widget> _detailsSlivers(ErrorGroup group, InsightsPeriod period, DateTime now) {
    final bars = hourBuckets(group.events, period, now);
    final appText = group.app.isEmpty ? 'программа неизвестна' : group.app;
    final routeText = group.route == ErrorRoute.block ? 'заблокировано' : 'идёт ${group.route.long}';
    final withDate = period == InsightsPeriod.week;
    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                group.target,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: RescueColors.text),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$appText · $routeText · ${group.count} ${errorsWord(group.count)} ${periodPhrase(period)}',
              style: RescueText.smallSecondary,
            ),
            const SizedBox(height: 14),
            HourBars(
              key: const ValueKey('errors-hour-bars'),
              counts: bars.counts,
              title: bars.title,
              startLabel: bars.start,
              endLabel: bars.end,
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
      SliverList.builder(
        itemCount: group.events.length,
        itemBuilder: (context, i) => _EventRow(event: group.events[i], now: now, withDate: withDate),
      ),
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 14),
            _RawLines(key: ValueKey('raw-${group.key}'), events: group.events),
            const SizedBox(height: 14),
            _Actions(group: group, period: period),
          ],
        ),
      ),
    ];
  }
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
      title = 'Ошибки по 5 минут';
      startLabel = hhmm(start);
      endLabel = 'сейчас';
    case InsightsPeriod.day:
      n = 24;
      start = DateTime(now.year, now.month, now.day, now.hour).subtract(const Duration(hours: 23));
      index = (t) => t.difference(start).inMinutes ~/ 60;
      title = 'Ошибки по часам';
      startLabel = '${sameDay(start, now) ? 'сегодня' : 'вчера'} ${start.hour.toString().padLeft(2, '0')}:00';
      endLabel = 'сейчас';
    case InsightsPeriod.week:
      n = 7;
      start = DateTime(now.year, now.month, now.day - 6);
      // По календарным дням; round — чтобы переход на летнее время не сдвигал день.
      index = (t) => (DateTime(t.year, t.month, t.day).difference(start).inHours / 24).round();
      title = 'Ошибки по дням';
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

class _Header extends StatelessWidget {
  const _Header({required this.period, required this.onChanged});

  final InsightsPeriod period;
  final ValueChanged<InsightsPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 240),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(header: true, child: const Text('Ошибки соединений', style: RescueText.pageTitle)),
                const SizedBox(height: 2),
                const Text(
                  'Что не смогло подключиться. Хранится только на этом компьютере, 7 дней.',
                  style: RescueText.pageSubtitle,
                ),
              ],
            ),
          ),
          PeriodSwitch<InsightsPeriod>(
            options: [for (final p in InsightsPeriod.values) (p, p.title)],
            value: period,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
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

    // На узком окне — два в ряд, а не столбиком.
    return RescueGrid(
      minItemWidth: 150,
      children: [
        StatTile(label: 'Всего ошибок', value: list == null ? '—' : '${countErrors(list)}'),
        StatTile(
          label: 'Через VPN',
          value: count((e) => e.route == ErrorRoute.vpn),
          valueColor: RescueColors.softAccentText,
        ),
        StatTile(
          label: 'Мимо VPN',
          value: count((e) => e.route == ErrorRoute.direct),
          valueColor: RescueColors.bypassText,
        ),
        StatTile(
          label: 'Замирания связи',
          value: count((e) => e.kind == ErrorKind.stall),
          valueColor: RescueColors.warningText,
        ),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => RescueCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(text, style: RescueText.body, textAlign: TextAlign.center),
    ),
  );
}

class _GroupsTitle extends StatelessWidget {
  const _GroupsTitle();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Row(
      children: [
        Expanded(child: Text('По сайтам и программам', style: RescueText.cardTitle)),
        SizedBox(width: 8),
        Text('сначала частые', style: RescueText.caption),
      ],
    ),
  );
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.selected, required this.now, required this.onTap});

  final ErrorGroup group;
  final bool selected;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final byApp = group.key.startsWith('app:');
    final who = byApp ? 'сайт неизвестен' : (group.app.isEmpty ? 'программа неизвестна' : group.app);
    final last = sameDay(group.last, now)
        ? 'в ${hhmm(group.last)}'
        : '${dayMonthShort(group.last)} в ${hhmm(group.last)}';
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: selected ? RescueColors.accent : RescueColors.line),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${group.target}, $who, ${group.route.long}, ${group.count} ${errorsWord(group.count)}',
        onTap: onTap,
        child: ExcludeSemantics(
          child: Material(
            color: selected ? RescueColors.softAccent : RescueColors.background,
            shape: shape,
            child: InkWell(
              customBorder: shape,
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            group.target,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RescueText.bodyStrong,
                          ),
                          Text(
                            '$who · последняя $last',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RescueText.caption,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    routeTag(group.route),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 36),
                      child: Text(
                        '${group.count}',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: group.count > 3 ? RescueColors.importantText : RescueColors.warningText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
      constraints: const BoxConstraints(minHeight: 40),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: RescueColors.rowLine)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: withDate ? 100 : 60,
            child: Text(withDate ? eventTime(e.time, now) : hhmm(e.time), style: monoStyle, maxLines: 1),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 13,
            child: Text(eventWhat(e), style: RescueText.small, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 10,
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
    final radius = BorderRadius.circular(12);
    return Container(
      decoration: BoxDecoration(
        color: RescueColors.background,
        border: Border.all(color: RescueColors.line),
        borderRadius: radius,
      ),
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
                        color: RescueColors.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Сырые строки',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: RescueColors.textTertiary),
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

    Widget addButton(SplitTarget target, String label, String done) {
      final already = current == target;
      return OutlinedButton(
        onPressed: item == null || already
            ? null
            : () {
                ref.read(splitTunnelProvider.notifier).add(target, item.kind, item.value);
                ScaffoldMessenger.maybeOf(
                  context,
                )?.showSnackBar(SnackBar(content: Text('Добавлено в «${target.title}»: ${item.value}')));
              },
        child: Text(already ? done : label),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        addButton(SplitTarget.bypass, 'Пустить мимо VPN', 'Уже мимо VPN'),
        addButton(SplitTarget.via, 'Всегда через VPN', 'Уже через VPN'),
        OutlinedButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: ownerSummary(group, period, DateTime.now())));
            if (!context.mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('Скопировано: сайт, программа, путь, виды ошибок и время, без IP')),
            );
          },
          child: const Text('Скопировать для владельца сервера'),
        ),
      ],
    );
  }
}
