import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/common/pinned_scroll.dart';
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
/// Без бокового меню: каркас (RescueShell) подключается снаружи. Если области раздела хватает
/// ([pinnedMinWidth] × [pinnedMinHeight]), закреплены заголовок с периодом, сводка, шапка списка,
/// название, график и кнопки подробностей, а прокручиваются только группы и события — каждая
/// колонка внутри своей карточки. Меньше — прокручивается вся страница (рядом, если шире
/// [wideFrom], иначе друг под другом), длинные списки обрезаны с кнопкой «Показать ещё».
class ErrorsPage extends HookConsumerWidget {
  const ErrorsPage({super.key, this.initialPeriod = InsightsPeriod.day});

  final InsightsPeriod initialPeriod;

  static const wideFrom = 860.0;

  /// Больше событий в подробностях не показываем: это для глаз, сырые строки — ниже.
  static const maxEvents = 100;

  /// Область ниже этой (но не меньше [pinnedMinHeight]) — «тесная»: сводка без пояснения.
  static const denseBelow = 700.0;

  /// На маленьком окне (прокрутка всей страницы) сначала показываем столько, дальше — «Показать ещё».
  static const compactStep = 30;

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
          final pinned = isPinnedLayout(constraints);
          // Невысокая область: сводка без пояснения и теснее, чтобы спискам осталось место.
          final dense = pinned && constraints.maxHeight < denseBelow;
          final gap = SizedBox(height: dense ? 12 : 20);
          final top = [header, gap, _Stats(events: events.valueOrNull, compact: dense), gap];
          if (placeholder != null || group == null) {
            return SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...top, ?placeholder]),
            );
          }
          final list = _GroupList(
            groups: groups!,
            selected: group,
            onSelect: (g) => selectedKey.value = g.key,
            pinned: pinned,
          );
          final details = _Details(
            key: ValueKey('details-${group.key}'),
            group: group,
            period: period.value,
            now: now,
            pinned: pinned,
          );
          if (pinned) {
            // Всё закреплено, колонки делят оставшуюся высоту и прокручиваются сами.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...top,
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 10, child: list),
                      const SizedBox(width: 20),
                      Expanded(flex: 13, child: details),
                    ],
                  ),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...top,
                if (constraints.maxWidth < wideFrom) ...[
                  list,
                  const SizedBox(height: 20),
                  details,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 10, child: list),
                      const SizedBox(width: 20),
                      Expanded(flex: 13, child: details),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
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
  const _Stats({required this.events, this.compact = false});

  /// null — ещё читаются.
  final List<ErrorEvent>? events;

  /// Без пояснения под числами (невысокое окно).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final list = events;
    String count(bool Function(ErrorEvent e) test) {
      if (list == null) return '—';
      return '${countErrors(list.where((e) => e.kind != ErrorKind.suppressed && test(e)))}';
    }

    return RescueCard(
      semanticLabel: 'Сводка',
      padding: compact ? const EdgeInsets.symmetric(vertical: 14, horizontal: 20) : const EdgeInsets.all(20),
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
          if (!compact) ...[
            const SizedBox(height: 14),
            const Text(
              'Что не смогло подключиться. Хранится только на этом компьютере, 7 дней.',
              style: RescueText.caption,
            ),
          ],
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
/// [pinned] — шапка закреплена, группы прокручиваются внутри карточки (нужна ограниченная высота);
/// иначе карточка по высоте списка, но не больше [ErrorsPage.compactStep] групп с «Показать ещё».
class _GroupList extends HookWidget {
  const _GroupList({required this.groups, required this.selected, required this.onSelect, required this.pinned});

  final List<ErrorGroup> groups;
  final ErrorGroup selected;
  final ValueChanged<ErrorGroup> onSelect;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final limit = useState(ErrorsPage.compactStep);
    final most = groups.fold<int>(1, (m, g) => g.count > m ? g.count : m);
    if (pinned) {
      return DeepList(
        title: 'По сайтам и программам',
        count: '${groups.length}',
        semanticLabel: 'Список',
        radius: 36,
        children: [
          Expanded(
            child: PinnedList(
              key: const ValueKey('errors-groups-list'),
              itemCount: groups.length,
              spacing: 10,
              itemBuilder: (_, i) => _tile(groups[i], most),
            ),
          ),
        ],
      );
    }
    final shown = groups.take(limit.value).toList();
    return DeepList(
      title: 'По сайтам и программам',
      count: '${groups.length}',
      semanticLabel: 'Список',
      radius: 36,
      children: [
        for (final g in shown) _tile(g, most),
        if (groups.length > shown.length)
          _MoreButton(
            key: const ValueKey('errors-groups-more'),
            shown: shown.length,
            total: groups.length,
            onDeep: true,
            onPressed: () => limit.value += ErrorsPage.compactStep,
          ),
      ],
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
///
/// [pinned]: название, подпись, график, «Сырые строки» и кнопки закреплены, события прокручиваются
/// внутри карточки (раскрытые сырые строки занимают их место). Иначе всё идёт подряд, события
/// обрезаны до [ErrorsPage.compactStep] с «Показать ещё».
class _Details extends HookWidget {
  const _Details({super.key, required this.group, required this.period, required this.now, required this.pinned});

  final ErrorGroup group;
  final InsightsPeriod period;
  final DateTime now;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final rawOpen = useState(false);
    final limit = useState(ErrorsPage.compactStep);
    final bars = hourBuckets(group.events, period, now);
    final appText = group.app.isEmpty ? 'программа неизвестна' : group.app;
    final routeText = group.route == ErrorRoute.block ? 'заблокировано' : 'идёт ${group.route.long}';
    final withDate = period == InsightsPeriod.week;
    final cap = group.events.length < ErrorsPage.maxEvents ? group.events.length : ErrorsPage.maxEvents;
    // Все события (до cap) — для своего списка с прокруткой; иначе только первые, остальное по кнопке.
    final shownAll = group.events.take(cap).toList();
    final shownFew = group.events.take(limit.value > cap ? cap : limit.value).toList();
    final total = bars.counts.fold<int>(0, (s, v) => s + v);
    final summary = Text(
      '$appText · $routeText · ${group.count} ${errorsWord(group.count)} ${periodPhrase(period)}',
      style: RescueText.smallSecondary,
    );
    Widget chart(double height) => HourBars(
      key: const ValueKey('errors-hour-bars'),
      counts: bars.counts,
      title: bars.title.toUpperCase(),
      startLabel: bars.start,
      endLabel: bars.end,
      height: height,
      semanticLabel: 'Ошибки ${bars.title.toLowerCase()}: всего $total',
    );
    final note = group.events.length > cap
        ? Text('Показаны последние $cap из ${group.events.length}', style: RescueText.caption)
        : null;
    void toggleRaw() => rawOpen.value = !rawOpen.value;

    // Всё подряд: для прокрутки всей страницы и для совсем низкой колонки (прокручивается карточка).
    Widget inlineBody() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        summary,
        const SizedBox(height: 16),
        chart(70),
        const SizedBox(height: 12),
        for (final e in shownFew) _EventRow(event: e, now: now, withDate: withDate),
        if (shownFew.length < cap)
          _MoreButton(
            key: const ValueKey('errors-events-more'),
            shown: shownFew.length,
            total: group.events.length,
            onPressed: () => limit.value = shownFew.length + ErrorsPage.compactStep,
          ),
        if (shownFew.length >= cap && note != null) ...[const SizedBox(height: 8), note],
        const SizedBox(height: 16),
        _RawLines(key: ValueKey('raw-${group.key}'), events: group.events, open: rawOpen.value, onToggle: toggleRaw),
        const SizedBox(height: 16),
        _Actions(group: group, period: period),
      ],
    );

    if (pinned) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Подробности',
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Совсем низкая колонка: закреплённое не оставило бы места событиям — крутим карточку целиком.
            if (constraints.maxHeight < (constraints.maxWidth < 560 ? tightBelowNarrow : tightBelow)) {
              return _PinnedFolder(
                title: group.target,
                padding: 14,
                child: PinnedScroll(key: const ValueKey('errors-details-scroll'), child: inlineBody()),
              );
            }
            // Невысокая колонка: график ниже, поля уже, чтобы событиям осталось место.
            final low = constraints.maxHeight < 560;
            return _PinnedFolder(
              title: group.target,
              padding: low ? 14 : 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  summary,
                  SizedBox(height: low ? 8 : 16),
                  chart(low ? 40 : 70),
                  const SizedBox(height: 12),
                  Expanded(
                    child: rawOpen.value
                        ? _RawBody(key: ValueKey('raw-${group.key}'), events: group.events)
                        : PinnedList(
                            key: const ValueKey('errors-events-list'),
                            itemCount: shownAll.length + (note == null ? 0 : 1),
                            itemBuilder: (_, i) => i < shownAll.length
                                ? _EventRow(event: shownAll[i], now: now, withDate: withDate)
                                : Padding(padding: const EdgeInsets.only(top: 8), child: note),
                          ),
                  ),
                  SizedBox(height: low ? 10 : 16),
                  _Actions(
                    group: group,
                    period: period,
                    rawToggle: _RawToggle(open: rawOpen.value, onPressed: toggleRaw),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Подробности',
      child: FolderTabs<String>(
        tabs: [FolderTab(value: group.key, title: group.target)],
        value: group.key,
        onChanged: null,
        child: inlineBody(),
      ),
    );
  }

  /// Колонка ниже этой (с закладкой): закрепить график и кнопки нечем, прокручивается вся карточка.
  /// В узкой колонке кнопки переносятся на больше строк, поэтому нужно больше места.
  static const tightBelow = 400.0;
  static const tightBelowNarrow = 480.0;
}

/// Закладка с названием над карточкой, которая занимает всю высоту колонки (как [FolderTabs] с одной
/// неактивной закладкой, но с растягиваемой карточкой: внутри можно поставить [Expanded]).
class _PinnedFolder extends StatelessWidget {
  const _PinnedFolder({required this.title, required this.child, this.padding = 20});

  final String title;
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    const r = Radius.circular(28);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            decoration: const BoxDecoration(
              color: RescueColors.card,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: RescueText.tabTitle),
          ),
        ),
        Expanded(
          child: Container(
            key: const ValueKey('folder-tabs-card'),
            padding: EdgeInsets.all(padding),
            decoration: const BoxDecoration(
              color: RescueColors.card,
              borderRadius: BorderRadius.only(topRight: r, bottomLeft: r, bottomRight: r),
            ),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: RescueColors.text),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

/// «Показать ещё» под обрезанным списком: сколько показано из скольких.
class _MoreButton extends StatelessWidget {
  const _MoreButton({
    super.key,
    required this.shown,
    required this.total,
    required this.onPressed,
    this.onDeep = false,
  });

  final int shown;
  final int total;
  final VoidCallback onPressed;

  /// Стоит на тёмном списке (deep), а не на карточке.
  final bool onDeep;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      style: TextButton.styleFrom(foregroundColor: onDeep ? RescueColors.textOnDeep : RescueColors.text),
      onPressed: onPressed,
      child: Text('Показать ещё · $shown из $total'),
    ),
  );
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

/// «Сырые строки» одним блоком (прокрутка всей страницы): исходный текст ошибок ядра, свёрнуто по
/// умолчанию. Состояние хранит хозяин ([open], [onToggle]).
class _RawLines extends StatelessWidget {
  const _RawLines({super.key, required this.events, required this.open, required this.onToggle});

  final List<ErrorEvent> events;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return Container(
      decoration: BoxDecoration(color: RescueColors.deep, borderRadius: radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              borderRadius: radius,
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(
                        open ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
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
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: SelectableText(_rawText(events), style: monoStyle.copyWith(height: 1.6)),
            ),
        ],
      ),
    );
  }
}

/// Закреплённый вариант: кнопка «Сырые строки» в ряду кнопок, раскрытый текст ([_RawBody]) занимает
/// место списка событий.
class _RawToggle extends StatelessWidget {
  const _RawToggle({required this.open, required this.onPressed});

  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    expanded: open,
    child: TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: RescueColors.text),
      onPressed: onPressed,
      icon: Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 18),
      label: const Text('Сырые строки'),
    ),
  );
}

/// Раскрытые сырые строки в закреплённом режиме: тёмный блок, текст прокручивается внутри.
class _RawBody extends StatelessWidget {
  const _RawBody({super.key, required this.events});

  final List<ErrorEvent> events;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: RescueColors.deep, borderRadius: BorderRadius.circular(20)),
    child: PinnedScroll(
      key: const ValueKey('errors-raw-scroll'),
      padding: const EdgeInsets.fromLTRB(14, 12, 2, 12),
      child: SelectableText(_rawText(events), style: monoStyle.copyWith(height: 1.6)),
    ),
  );
}

/// Исходные строки ошибок ядра для «Сырых строк».
String _rawText(List<ErrorEvent> events) {
  /// Больше не нужно: это для глаз, а не для выгрузки.
  const max = 200;
  return [
    for (final e in events.take(max)) _rawLine(e),
    if (events.length > max) '… и ещё ${events.length - max}',
  ].join('\n');
}

String _rawLine(ErrorEvent e) {
  final where = [
    if (e.app.isNotEmpty) '[${e.app}]',
    if (e.target.isNotEmpty) e.host.isNotEmpty && e.port > 0 ? '${e.host}:${e.port}' : e.target,
    e.route.long,
  ].join(' ');
  final n = e.count > 1 ? ' (×${e.count})' : '';
  return '${hhmmss(e.time)} ${e.kind.name} $where: ${e.message.isEmpty ? e.kind.title : e.message}$n';
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.group, required this.period, this.rawToggle});

  final ErrorGroup group;
  final InsightsPeriod period;

  /// Ещё одна кнопка в конце ряда («Сырые строки» в закреплённом режиме).
  final Widget? rawToggle;

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
        ?rawToggle,
      ],
    );
  }
}
