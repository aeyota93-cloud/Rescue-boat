import 'dart:math' as math;

import 'package:hiddify/features/insights/model/insights_models.dart';

// Оценка «Здоровья подключения» по quality-*.jsonl. Формула — docs/redesign/contract.md, раздел 2.
// Окно делится на минуты: одна минута = замер vpn (5 выборок) + счётчики ядра.

/// Минута с оценкой не ниже — «хорошо», не ниже fairFrom — «средне», иначе «плохо».
const healthGoodFrom = 85;
const healthFairFrom = 60;

/// Пинг (медиана vpn): ≤80 мс → 100; 80–150 → линейно до 70; 150–300 → до 40; >300 → 20.
double pingScore(double ms) {
  if (ms <= 80) return 100;
  if (ms <= 150) return 100 - (ms - 80) / 70 * 30;
  if (ms <= 300) return 70 - (ms - 150) / 150 * 30;
  return 20;
}

/// Все выборки потерялись: пинга нет, считаем как худший (>300 мс).
const _noAnswerPingScore = 20.0;

/// Джиттер (ст. отклонение): ≤10 мс → 100; ≥60 мс → 40; между — линейно.
double jitterScore(double ms) {
  if (ms <= 10) return 100;
  if (ms >= 60) return 40;
  return 100 - (ms - 10) / 50 * 60;
}

/// Потери (доля 0..1): 0 → 100; ≥10 % → 0; между — линейно.
double lossScore(double fraction) {
  if (fraction <= 0) return 100;
  if (fraction >= 0.1) return 0;
  return 100 * (1 - fraction / 0.1);
}

/// Соединения без ошибок: 100 × (1 − errs/conns), при conns = 0 → 100.
double errorsScore(int errs, int conns) => conns <= 0 ? 100 : (100 * (1 - errs / conns)).clamp(0, 100).toDouble();

/// DNS: 100 × ok/(ok+fail), без запросов → 100.
double dnsScore(int ok, int fail) => ok + fail <= 0 ? 100 : 100 * ok / (ok + fail);

/// Общая = 0.25·пинг + 0.15·джиттер + 0.20·потери + 0.25·ошибки + 0.15·DNS.
/// Если части нет (нет замеров или счётчиков), веса остальных делятся заново; нет ничего — null.
double? overallScore({double? ping, double? jitter, double? loss, double? errors, double? dns}) {
  var sum = 0.0;
  var weights = 0.0;
  void add(double? score, double weight) {
    if (score == null) return;
    sum += score * weight;
    weights += weight;
  }

  add(ping, 0.25);
  add(jitter, 0.15);
  add(loss, 0.20);
  add(errors, 0.25);
  add(dns, 0.15);
  return weights == 0 ? null : sum / weights;
}

/// «Здоровье подключения» за 24 часа до now; тренд — к предыдущим 24 часам.
HealthSnapshot computeHealth(Iterable<QualityRecord> records, DateTime now) {
  final dayAgo = now.subtract(const Duration(hours: 24));
  final current = _minutes(records, dayAgo, now);
  if (current.isEmpty) return HealthSnapshot.empty;
  final previous = _Agg()..addAll(_minutes(records, now.subtract(const Duration(hours: 48)), dayAgo));

  final window = _Agg()..addAll(current);
  final cur = window.scores();
  if (cur.overall == null) return HealthSnapshot.empty;
  final prev = previous.scores();

  final bars = List.generate(5, (_) => _Bars());
  for (final m in current) {
    final s = (_Agg()..add(m)).scores();
    bars[0].add(s.overall);
    bars[1].add(s.ping);
    bars[2].add(s.stability);
    bars[3].add(s.errors);
    bars[4].add(s.dns);
  }

  HealthMetric metric(String title, double? score, double? prevScore, _Bars bar, String caption) => HealthMetric(
    title: title,
    score: score?.round(),
    good: bar.share(bar.good),
    fair: bar.share(bar.fair),
    poor: bar.share(bar.poor),
    caption: score == null ? 'нет данных' : caption,
    trend: score == null || prevScore == null ? 0 : score.round() - prevScore.round(),
  );

  final pingMs = window.ok.isEmpty ? null : _median(window.ok).round();
  final jitterMs = window.jitters.isEmpty ? null : _mean(window.jitters).round();
  final total = window.ok.length + window.lost;
  final lossPercent = total == 0 ? null : 100 * window.lost / total;

  return HealthSnapshot(
    overall: metric('Общая оценка', cur.overall, prev.overall, bars[0], _overallCaption(cur.overall, bars[0])),
    ping: metric('Пинг до сервера', cur.ping, prev.ping, bars[1], _pingCaption(window)),
    stability: metric(
      'Стабильность',
      cur.stability,
      prev.stability,
      bars[2],
      _stabilityCaption(jitterMs, lossPercent, window.outage),
    ),
    errorsFree: metric('Соединения без ошибок', cur.errors, prev.errors, bars[3], _errorsCaption(window)),
    dns: metric('DNS', cur.dns, prev.dns, bars[4], _dnsCaption(window)),
    pingMs: pingMs,
    jitterMs: jitterMs,
    lossPercent: lossPercent,
  );
}

/// Оценка по дням за days местных суток до now включительно, старые первыми.
List<DailyHealth> computeHistory(Iterable<QualityRecord> records, DateTime now, {int days = 30}) {
  final today = DateTime(now.year, now.month, now.day);
  final first = DateTime(today.year, today.month, today.day - (days - 1));
  final byDay = <DateTime, _Agg>{};
  for (final m in _minutes(records, first.subtract(const Duration(milliseconds: 1)), now)) {
    final t = m.time;
    byDay.putIfAbsent(DateTime(t.year, t.month, t.day), _Agg.new).add(m);
  }
  return [
    for (var i = 0; i < days; i++)
      () {
        final day = DateTime(first.year, first.month, first.day + i);
        final agg = byDay[day];
        return DailyHealth(
          day: day,
          score: agg?.scores().overall?.round(),
          errors: agg?.errs ?? 0,
          outageMinutes: agg?.outage ?? 0,
        );
      }(),
  ];
}

/// Проценты для подписей: 3%, 0,4%, 0%.
String formatPercent(double percent) {
  if (percent <= 0) return '0%';
  if (percent < 1) return '${math.max(0.1, (percent * 10).round() / 10).toStringAsFixed(1).replaceAll('.', ',')}%';
  return '${percent.round()}%';
}

String _overallCaption(double? score, _Bars bar) {
  if (score == null) return 'нет данных';
  if (score >= healthGoodFrom) return 'всё в порядке';
  return 'хорошо ${formatPercent(100 * bar.share(bar.good))} времени, плохо ${formatPercent(100 * bar.share(bar.poor))}';
}

String _pingCaption(_Agg w) {
  if (w.ok.isEmpty) return 'сервер не отвечал';
  final median = _median(w.ok).round();
  final low = _percentile(w.ok, 0.25).round();
  final high = _percentile(w.ok, 0.75).round();
  return low == high ? '$median мс' : '$median мс, обычно $low–$high';
}

String _stabilityCaption(int? jitterMs, double? lossPercent, int outageMinutes) => [
  if (jitterMs != null) 'разброс $jitterMs мс',
  if (lossPercent != null) lossPercent == 0 ? 'без потерь' : 'потери ${formatPercent(lossPercent)}',
  if (outageMinutes > 0) 'сервер не отвечал $outageMinutes мин',
].join(', ');

String _errorsCaption(_Agg w) {
  if (w.conns == 0) return 'соединений не было';
  if (w.errs == 0) return 'ошибок нет';
  return '${formatPercent(100 * w.errs / w.conns)} соединений с ошибкой';
}

String _dnsCaption(_Agg w) {
  final total = w.dnsOk + w.dnsFail;
  if (total == 0) return 'запросов не было';
  if (w.dnsFail == 0) return 'все адреса находятся';
  return '${formatPercent(100 * w.dnsFail / total)} адресов не нашлось';
}

class _Minute {
  _Minute(this.time);

  final DateTime time;
  final vpn = <int?>[];
  QualityCounters? counters;
}

/// Минуты с записями в (from, to], по порядку.
List<_Minute> _minutes(Iterable<QualityRecord> records, DateTime from, DateTime to) {
  final byKey = <int, _Minute>{};
  for (final r in records) {
    if (!r.time.isAfter(from) || r.time.isAfter(to)) continue;
    final key = r.time.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;
    final m = byKey.putIfAbsent(key, () => _Minute(r.time));
    switch (r) {
      case QualityProbe():
        if (r.isVpn) m.vpn.addAll(r.samples);
      case QualityCounters():
        final c = m.counters;
        m.counters = c == null
            ? r
            : QualityCounters(
                time: c.time,
                conns: c.conns + r.conns,
                errs: c.errs + r.errs,
                dnsOk: c.dnsOk + r.dnsOk,
                dnsFail: c.dnsFail + r.dnsFail,
              );
    }
  }
  final keys = byKey.keys.toList()..sort();
  return [for (final k in keys) byKey[k]!];
}

/// Сумма по минутам окна (или одной минуте).
class _Agg {
  final ok = <int>[];
  int lost = 0;

  /// Ст. отклонение vpn-выборок внутри каждой минуты (где удачных хотя бы две).
  final jitters = <double>[];

  /// Минуты, где все vpn-выборки потерялись.
  int outage = 0;
  bool hasCounters = false;
  int conns = 0;
  int errs = 0;
  int dnsOk = 0;
  int dnsFail = 0;

  void addAll(Iterable<_Minute> minutes) => minutes.forEach(add);

  void add(_Minute m) {
    final good = m.vpn.whereType<int>().toList();
    ok.addAll(good);
    lost += m.vpn.length - good.length;
    if (m.vpn.isNotEmpty && good.isEmpty) outage++;
    if (good.length >= 2) jitters.add(_stdDev(good));
    final c = m.counters;
    if (c != null) {
      hasCounters = true;
      conns += c.conns;
      errs += c.errs;
      dnsOk += c.dnsOk;
      dnsFail += c.dnsFail;
    }
  }

  _Scores scores() {
    final total = ok.length + lost;
    return _Scores(
      ping: total == 0 ? null : (ok.isEmpty ? _noAnswerPingScore : pingScore(_median(ok))),
      jitter: jitters.isEmpty ? null : jitterScore(_mean(jitters)),
      loss: total == 0 ? null : lossScore(lost / total),
      errors: hasCounters ? errorsScore(errs, conns) : null,
      dns: hasCounters ? dnsScore(dnsOk, dnsFail) : null,
    );
  }
}

class _Scores {
  const _Scores({this.ping, this.jitter, this.loss, this.errors, this.dns});

  final double? ping;
  final double? jitter;
  final double? loss;
  final double? errors;
  final double? dns;

  /// Строка «Стабильность» = среднее(джиттер, потери).
  double? get stability => switch ((jitter, loss)) {
    (final double j, final double l) => (j + l) / 2,
    (final double j, null) => j,
    (null, final double l) => l,
    _ => null,
  };

  double? get overall => overallScore(ping: ping, jitter: jitter, loss: loss, errors: errors, dns: dns);
}

class _Bars {
  int good = 0;
  int fair = 0;
  int poor = 0;

  void add(double? score) {
    if (score == null) return;
    final s = score.round();
    if (s >= healthGoodFrom) {
      good++;
    } else if (s >= healthFairFrom) {
      fair++;
    } else {
      poor++;
    }
  }

  double share(int n) {
    final total = good + fair + poor;
    return total == 0 ? 0 : n / total;
  }
}

double _mean(List<num> v) => v.fold<double>(0, (s, x) => s + x) / v.length;

double _stdDev(List<int> v) {
  final m = _mean(v);
  return math.sqrt(v.fold<double>(0, (s, x) => s + (x - m) * (x - m)) / v.length);
}

double _median(List<int> v) => _percentile(v, 0.5);

/// Перцентиль с линейной интерполяцией между соседними значениями.
double _percentile(List<int> v, double q) {
  final s = [...v]..sort();
  final pos = (s.length - 1) * q;
  final i = pos.floor();
  if (i + 1 >= s.length) return s.last.toDouble();
  return s[i] + (s[i + 1] - s[i]) * (pos - i);
}
