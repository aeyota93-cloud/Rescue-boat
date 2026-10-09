import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/insights/widget/insights_format.dart';
import 'package:hiddify/features/overview/notifier/vpn_status.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: «Обзор» — подключение, здоровье, оценка по дням, последние ошибки, правила, подписка.
///
/// Без бокового меню: каркас (RescueShell) подключается снаружи. Трафика по программам и сайтам
/// здесь нет и не будет (решение пользователя), только факты из файлов ядра.
class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: RescueColors.background,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(),
            SizedBox(height: 16),
            RescueGrid(minItemWidth: 420, spacing: 16, children: [_HealthCard(), _HistoryCard()]),
            SizedBox(height: 16),
            _ErrorsCard(),
            SizedBox(height: 16),
            RescueGrid(minItemWidth: 300, spacing: 16, children: [_RulesCard(), _SubscriptionCard()]),
          ],
        ),
      ),
    );
  }
}

const _noData = 'Нет данных: замеры идут, пока VPN включён';

/// Переход по маршруту, если приложение с роутером (в тестах страница может жить без него).
void _go(BuildContext context, String location) => GoRouter.maybeOf(context)?.go(location);

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: RescueText.smallSecondary),
  );
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStatusProvider);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          Semantics(header: true, child: const Text('Обзор', style: RescueText.pageTitle)),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ConnectionPill(
                connected: vpn.connected,
                busy: vpn.busy,
                label: vpn.label,
                onChanged: vpn.canToggle ? (on) => _toggleVpn(context, ref, on) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Включить или выключить VPN — как большая кнопка старой главной, но без её диалогов про профили.
Future<void> _toggleVpn(BuildContext context, WidgetRef ref, bool on) async {
  final connection = ref.read(connectionNotifierProvider.notifier);
  if (!on) return connection.toggleConnection();
  if (ref.read(activeProfileProvider).valueOrNull == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: const Text('Сначала добавьте подписку'),
        action: SnackBarAction(label: 'Серверы', onPressed: () => _go(context, '/servers')),
      ),
    );
    return;
  }
  if (!await ref.read(dialogNotifierProvider.notifier).showExperimentalFeatureNotice()) return;
  await connection.toggleConnection();
}

// ---------------------------------------------------------------- Здоровье

class _HealthCard extends ConsumerWidget {
  const _HealthCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider);
    final snapshot = health.valueOrNull;
    final Widget body;
    if (snapshot != null && !snapshot.isEmpty) {
      // Как в макете: две колонки, на узком окне — одна.
      body = LayoutBuilder(
        builder: (context, constraints) => RescueGrid(
          minItemWidth: math.max(160, (constraints.maxWidth - 24) / 2 - 1),
          spacing: 24,
          runSpacing: 16,
          children: [
            for (final m in snapshot.metrics)
              ScoreRow(
                name: m.title,
                value: m.score?.toString() ?? '—',
                trend: m.score == null ? null : m.trend,
                good: m.good,
                fair: m.fair,
                poor: m.poor,
                caption: m.caption,
                emphasized: identical(m, snapshot.overall),
              ),
          ],
        ),
      );
    } else if (snapshot != null) {
      body = const _Note(_noData);
    } else if (health.hasError) {
      body = const _Note('Не удалось прочитать замеры');
    } else {
      body = const _Note('Читаем замеры…');
    }
    return RescueCard(
      semanticLabel: 'Здоровье подключения',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Здоровье подключения', trailingText: 'за 24 часа'),
          const SizedBox(height: 14),
          body,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Оценка по дням

class _HistoryCard extends ConsumerWidget {
  const _HistoryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(healthHistoryProvider);
    final days = history.valueOrNull;
    final Widget body;
    if (days != null && days.any((d) => d.score != null)) {
      body = _chart(days);
    } else if (days != null) {
      body = const _Note(_noData);
    } else if (history.hasError) {
      body = const _Note('Не удалось прочитать замеры');
    } else {
      body = const _Note('Читаем замеры…');
    }
    return RescueCard(
      semanticLabel: 'Оценка по дням',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: 'Оценка по дням', trailingText: 'последние ${days?.length ?? 30} дней'),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }

  static Widget _chart(List<DailyHealth> days) {
    final scores = [for (final d in days) d.score?.toDouble()];
    final known = scores.whereType<double>();
    final lo = known.reduce(math.min);
    final hi = known.reduce(math.max);
    // Низ шкалы — ближайший десяток под минимумом, но не выше 70: так обычные дни не «прыгают».
    final minY = (((lo - 5) / 10).floor() * 10).clamp(0, 70).toDouble();
    final step = 100 - minY > 50 ? 20.0 : 10.0;
    final ticks = [for (var t = 100.0; t >= minY; t -= step) t];

    // Отметки: красная — сервер был недоступен, оранжевая — были ошибки. Подпись — у худшего сбоя.
    var worst = -1;
    for (final (i, d) in days.indexed) {
      if (d.score != null && d.outageMinutes > 0 && (worst < 0 || d.outageMinutes > days[worst].outageMinutes)) {
        worst = i;
      }
    }
    final markers = [
      for (final (i, d) in days.indexed)
        if (d.outageMinutes > 0)
          LineChartMarker(
            index: i,
            color: RescueColors.poor,
            label: i == worst ? 'сервер был недоступен ${minutesText(d.outageMinutes)}' : null,
          )
        else if (d.errors > 0)
          LineChartMarker(index: i, color: RescueColors.fair),
    ];
    final outages = days.where((d) => d.outageMinutes > 0).length;
    final last = known.last.round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LineChart(
          values: scores,
          minY: minY,
          yTicks: ticks,
          xLabels: [
            dayMonthShort(days.first.day),
            if (days.length > 2) dayMonthShort(days[days.length ~/ 2].day),
            if (days.length > 1) dayMonthShort(days.last.day),
          ],
          markers: markers,
          semanticLabel:
              'График оценки за ${days.length} дней: от ${lo.round()} до ${hi.round()}, последняя $last'
              '${outages > 0 ? '; сервер был недоступен в $outages ${plural(outages, 'день', 'дня', 'дней')}' : ''}',
        ),
        const SizedBox(height: 10),
        const ChartLegend(
          items: [
            ChartLegendItem(color: RescueColors.accent, label: 'Общая оценка', line: true),
            ChartLegendItem(color: RescueColors.poor, label: 'Серьёзный сбой'),
            ChartLegendItem(color: RescueColors.fair, label: 'Были ошибки'),
          ],
        ),
      ],
    );
  }
}

/// «40 мин», «2 ч 5 мин».
String minutesText(int minutes) {
  if (minutes < 60) return '$minutes мин';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h ч' : '$h ч $m мин';
}

// ---------------------------------------------------------------- Ошибки

class _ErrorsCard extends ConsumerWidget {
  const _ErrorsCard();

  static const _shown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hour = ref.watch(errorCountProvider(const Duration(hours: 1)));
    final day = ref.watch(errorCountProvider(const Duration(days: 1)));
    final events = ref.watch(errorEventsProvider(InsightsPeriod.day));
    final list = events.valueOrNull;
    final now = DateTime.now();

    final Widget body;
    if (list != null) {
      final recent = list.where((e) => e.kind != ErrorKind.suppressed).take(_shown).toList();
      body = recent.isEmpty
          ? const _Note('Ошибок за сутки нет')
          : RescueTable(
              columns: const [
                RescueColumn('Время', width: 60),
                RescueColumn('Программа', flex: 1.1),
                RescueColumn('Сайт или адрес', flex: 1.4),
                RescueColumn('Что случилось', flex: 1.6),
                RescueColumn('Путь', width: 80, alignEnd: true),
              ],
              rows: [
                for (final e in recent)
                  RescueTableRow(
                    cells: [
                      Text(sameDay(e.time, now) ? hhmm(e.time) : dayMonthShort(e.time), style: monoStyle),
                      Text(e.app.isEmpty ? '—' : e.app),
                      Text(e.target.isEmpty ? '—' : e.target, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(eventWhat(e), style: const TextStyle(color: RescueColors.textTertiary)),
                      routeTag(e.route),
                    ],
                  ),
              ],
            );
    } else if (events.hasError) {
      body = const _Note('Не удалось прочитать журнал ошибок');
    } else {
      body = const _Note('Читаем журнал ошибок…');
    }

    return RescueCard(
      semanticLabel: 'Ошибки соединений',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Ошибки соединений',
            badges: [
              RescueBadge(label: '$hour за час', kind: hour > 0 ? RescueBadgeKind.important : RescueBadgeKind.neutral),
              RescueBadge(label: '$day за сутки'),
            ],
            actionLabel: 'Все ошибки',
            onAction: () => _go(context, '/errors'),
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Правила

class _RulesCard extends ConsumerWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitTunnelProvider);
    int size(SplitList l) => l.apps.length + l.domains.length + l.ips.length;
    final via = size(split.via);
    final bypass = size(split.bypass);
    final total = via + bypass;
    final defaults = {for (final a in defaultBypassApps) a.toLowerCase()};
    final games = split.bypass.apps.where((a) => defaults.contains(a.toLowerCase())).length;

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: 'Правила', actionLabel: 'Открыть', onAction: () => _go(context, '/split')),
        const SizedBox(height: 6),
        _RuleRow(name: 'Через VPN', count: via, color: RescueColors.accent, onTap: () => _go(context, '/split')),
        const SizedBox(height: 4),
        _RuleRow(name: 'Мимо VPN', count: bypass, color: RescueColors.teal, onTap: () => _go(context, '/split')),
        if (games > 0) ...[
          const SizedBox(height: 8),
          Text('из них $games — игры и лаунчеры из стандартного списка', style: RescueText.caption),
        ],
      ],
    );
    final donut = DonutChart(
      centerValue: '$total',
      centerLabel: plural(total, 'правило', 'правила', 'правил'),
      semanticLabel: 'Правил: $via через VPN, $bypass мимо VPN',
      segments: [
        DonutSegment(value: via.toDouble(), color: RescueColors.accent, label: 'через VPN'),
        DonutSegment(value: bypass.toDouble(), color: RescueColors.teal, label: 'мимо VPN'),
      ],
    );

    return RescueCard(
      semanticLabel: 'Правила',
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 220 + 20 + 170
            ? Row(
                children: [
                  Expanded(child: list),
                  const SizedBox(width: 20),
                  donut,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  list,
                  const SizedBox(height: 20),
                  Center(child: donut),
                ],
              ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.name, required this.count, required this.color, required this.onTap});

  final String name;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Semantics(
      button: true,
      label: '$name: $count',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: RescueColors.background,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(name, style: RescueText.body)),
                  Text('$count', style: RescueText.bodyStrong),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Подписка

/// Больше этого — «без ограничения» (как в старой карточке профиля).
const _unlimitedBytes = 10 * 1099511627776;

/// «48 ГБ», «4,5 ГБ», «820 МБ».
String sizeText(int bytes) {
  const gb = 1073741824;
  const mb = 1048576;
  if (bytes >= gb) {
    final v = bytes / gb;
    return '${v < 10 ? v.toStringAsFixed(1).replaceAll('.', ',').replaceAll(',0', '') : v.round()} ГБ';
  }
  return '${(bytes / mb).round()} МБ';
}

class _SubscriptionCard extends ConsumerWidget {
  const _SubscriptionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeProfileProvider);
    final profile = active.valueOrNull;
    final now = DateTime.now();

    final children = <Widget>[
      SectionHeader(title: 'Подписка', actionLabel: 'Серверы', onAction: () => _go(context, '/servers')),
    ];
    if (profile == null) {
      children.add(_Note(active.isLoading ? 'Читаем подписку…' : 'Подписка не добавлена'));
    } else {
      final (host, sub) = switch (profile) {
        RemoteProfileEntity(:final url, :final subInfo) => (Uri.tryParse(url)?.host ?? '', subInfo),
        LocalProfileEntity() => ('', null),
      };
      children.add(Text([profile.name, if (host.isNotEmpty) host].join(' · '), style: RescueText.smallSecondary));
      if (sub != null) {
        final limited = sub.total > 0 && sub.total <= _unlimitedBytes;
        children.addAll([
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              text: sizeText(sub.consumption),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: RescueColors.text),
              children: [
                TextSpan(
                  text: limited ? ' из ${sizeText(sub.total)}' : ' без ограничения',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: RescueColors.textSecondary),
                ),
              ],
            ),
          ),
          if (limited) ...[
            const SizedBox(height: 10),
            RescueProgressBar(
              value: sub.ratio,
              height: 8,
              color: sub.ratio >= 0.9
                  ? RescueColors.poor
                  : sub.ratio >= 0.75
                  ? RescueColors.fair
                  : RescueColors.good,
            ),
          ],
        ]);
      }
      final updated = profile.lastUpdate;
      final facts = [
        if (sub != null)
          if (sub.isExpired)
            'Срок истёк ${dayMonthLong(sub.expire)}'
          else if (sub.remaining.inDays > 3650)
            'Без срока'
          else
            'Действует до ${dayMonthLong(sub.expire)}${sub.expire.year != now.year ? ' ${sub.expire.year}' : ''}',
        'обновлена ${sameDay(updated, now) ? 'в ${hhmm(updated)}' : '${dayMonthShort(updated)} в ${hhmm(updated)}'}',
      ];
      final line = facts.join(' · ');
      children.addAll([
        const SizedBox(height: 10),
        Text(
          line[0].toUpperCase() + line.substring(1),
          style: TextStyle(
            fontSize: 13,
            color: sub?.isExpired ?? false ? RescueColors.poor : RescueColors.textSecondary,
          ),
        ),
      ]);
    }

    return RescueCard(
      semanticLabel: 'Подписка',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}
