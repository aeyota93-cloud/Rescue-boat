import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/insights/data/health_score.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';

final now = DateTime(2025, 10, 9, 12);

/// Одна минута: vpn-замер (если есть), direct-замер (формула его не учитывает) и счётчики (если есть).
List<QualityRecord> minute(DateTime t, List<int?>? vpn, {int? conns, int errs = 0, int dnsOk = 0, int dnsFail = 0}) => [
  if (vpn != null) QualityProbe(time: t, path: 'vpn', samples: vpn),
  QualityProbe(time: t, path: 'direct', samples: const [500, null, null, null, null]),
  if (conns != null) QualityCounters(time: t, conns: conns, errs: errs, dnsOk: dnsOk, dnsFail: dnsFail),
];

DateTime ago(Duration d) => now.subtract(d);
DateTime minAgo(int m) => ago(Duration(minutes: m));

void main() {
  group('границы формулы', () {
    test('пинг: 80 / 150 / 300 мс', () {
      expect(pingScore(0), 100);
      expect(pingScore(80), 100);
      expect(pingScore(115), closeTo(85, 1e-9));
      expect(pingScore(150), closeTo(70, 1e-9));
      expect(pingScore(225), closeTo(55, 1e-9));
      expect(pingScore(300), closeTo(40, 1e-9));
      expect(pingScore(301), 20);
      expect(pingScore(3000), 20);
    });

    test('джиттер: 10 / 60 мс', () {
      expect(jitterScore(0), 100);
      expect(jitterScore(10), 100);
      expect(jitterScore(35), closeTo(70, 1e-9));
      expect(jitterScore(60), 40);
      expect(jitterScore(200), 40);
    });

    test('потери: 0 / 10 %', () {
      expect(lossScore(0), 100);
      expect(lossScore(0.05), closeTo(50, 1e-9));
      expect(lossScore(0.1), 0);
      expect(lossScore(0.5), 0);
    });

    test('ошибки: conns = 0 → 100', () {
      expect(errorsScore(0, 0), 100);
      expect(errorsScore(5, 0), 100);
      expect(errorsScore(3, 100), closeTo(97, 1e-9));
      expect(errorsScore(10, 10), 0);
    });

    test('DNS: нет запросов → 100', () {
      expect(dnsScore(0, 0), 100);
      expect(dnsScore(88, 0), 100);
      expect(dnsScore(3, 1), 75);
      expect(dnsScore(0, 4), 0);
    });

    test('веса общей оценки', () {
      double only(String part) => overallScore(
        ping: part == 'ping' ? 100 : 0,
        jitter: part == 'jitter' ? 100 : 0,
        loss: part == 'loss' ? 100 : 0,
        errors: part == 'errors' ? 100 : 0,
        dns: part == 'dns' ? 100 : 0,
      )!;
      expect(only('ping'), closeTo(25, 1e-9));
      expect(only('jitter'), closeTo(15, 1e-9));
      expect(only('loss'), closeTo(20, 1e-9));
      expect(only('errors'), closeTo(25, 1e-9));
      expect(only('dns'), closeTo(15, 1e-9));
      // Нет части — веса остальных делятся заново.
      expect(overallScore(ping: 100, errors: 0), closeTo(50, 1e-9));
      expect(overallScore(), isNull);
    });

    test('проценты в подписях', () {
      expect(formatPercent(0), '0%');
      expect(formatPercent(0.01), '0,1%');
      expect(formatPercent(0.44), '0,4%');
      expect(formatPercent(3.2), '3%');
      expect(formatPercent(25), '25%');
    });
  });

  group('снимок за 24 часа', () {
    test('нет данных — HealthSnapshot.empty', () {
      expect(computeHealth(const [], now), same(HealthSnapshot.empty));
      // Только старше суток (ровно 24 часа назад — уже не в окне).
      expect(
        computeHealth(minute(ago(const Duration(hours: 24)), [50, 50, 50, 50, 50], conns: 5), now).isEmpty,
        isTrue,
      );
      // Только direct-замеры: оценивать нечего.
      expect(computeHealth(minute(minAgo(1), null), now), same(HealthSnapshot.empty));
      expect(HealthSnapshot.empty.metrics.map((m) => m.title), [
        'Общая оценка',
        'Пинг до сервера',
        'Стабильность',
        'Соединения без ошибок',
        'DNS',
      ]);
    });

    test('хорошие сутки: оценки, сырые значения и подписи', () {
      final s = computeHealth([
        for (var i = 1; i <= 3; i++) ...minute(minAgo(i), [48, 50, 52, 49, 51], conns: 100, errs: 3, dnsOk: 88),
      ], now);
      expect(s.isEmpty, isFalse);
      expect(s.pingMs, 50);
      expect(s.jitterMs, 1);
      expect(s.lossPercent, 0);
      expect(s.ping.score, 100);
      expect(s.stability.score, 100);
      expect(s.errorsFree.score, 97);
      expect(s.dns.score, 100);
      expect(s.overall.score, 99); // 25 + 15 + 20 + 0.25·97 + 15 = 99.25
      expect(s.ping.caption, '50 мс, обычно 49–51');
      expect(s.stability.caption, 'разброс 1 мс, без потерь');
      expect(s.errorsFree.caption, '3% соединений с ошибкой');
      expect(s.dns.caption, 'все адреса находятся');
      expect(s.overall.caption, 'всё в порядке');
      expect((s.overall.good, s.overall.fair, s.overall.poor), (1.0, 0.0, 0.0));
      expect(s.overall.trend, 0, reason: 'прошлых суток нет');
    });

    test('доли хорошо/средне/плохо по минутам и минута без ответа', () {
      final s = computeHealth([
        ...minute(minAgo(4), [50, 50, 50, 50, 50]), // 100 — хорошо
        ...minute(minAgo(3), [50, 50, 50, 50, 50]), // 100 — хорошо
        ...minute(minAgo(2), [200, 200, 200, 200, 200]), // пинг 60, общая 83 — средне
        ...minute(minAgo(1), [null, null, null, null, null]), // сервер не ответил — плохо
      ], now);

      expect((s.overall.good, s.overall.fair, s.overall.poor), (0.5, 0.25, 0.25));
      expect((s.ping.good, s.ping.fair, s.ping.poor), (0.5, 0.25, 0.25));
      expect((s.stability.good, s.stability.fair, s.stability.poor), (0.75, 0.0, 0.25));
      expect(s.lossPercent, 25);
      expect(s.pingMs, 50);
      // Пинг 100, джиттер 100, потери 25% → 0; счётчиков нет: (25 + 15 + 0) / 0.6.
      expect(s.overall.score, 67);
      expect(s.overall.caption, 'хорошо 50% времени, плохо 25%');
      expect(s.stability.caption, 'разброс 0 мс, потери 25%, сервер не отвечал 1 мин');
      expect(s.errorsFree.score, isNull);
      expect(s.errorsFree.caption, 'нет данных');
      expect(s.dns.score, isNull);
    });

    test('все выборки потерялись: пинг как худший', () {
      final s = computeHealth(minute(minAgo(1), [null, null, null, null, null]), now);
      expect(s.ping.score, 20);
      expect(s.ping.caption, 'сервер не отвечал');
      expect(s.pingMs, isNull);
      expect(s.jitterMs, isNull);
      expect(s.lossPercent, 100);
    });

    test('ровный пинг — подпись без диапазона', () {
      final s = computeHealth(minute(minAgo(1), [300, 300, 300, 300, 300]), now);
      expect(s.ping.score, 40);
      expect(s.ping.caption, '300 мс');
    });

    test('conns = 0 и нет DNS-запросов → 100', () {
      final s = computeHealth(minute(minAgo(1), [50, 50, 50, 50, 50], conns: 0), now);
      expect(s.errorsFree.score, 100);
      expect(s.errorsFree.caption, 'соединений не было');
      expect(s.dns.score, 100);
      expect(s.dns.caption, 'запросов не было');
    });

    test('ошибки DNS и соединений в подписях', () {
      final s = computeHealth(minute(minAgo(1), null, conns: 10, dnsOk: 3, dnsFail: 1), now);
      expect(s.dns.score, 75);
      expect(s.dns.caption, '25% адресов не нашлось');
      expect(s.errorsFree.caption, 'ошибок нет');
      expect(s.ping.score, isNull, reason: 'замеров не было, только счётчики');
      expect(s.overall.score, isNotNull);
    });

    test('тренд к прошлым суткам', () {
      final s = computeHealth([
        ...minute(ago(const Duration(hours: 30)), [115, 115, 115, 115, 115]), // пинг 85
        ...minute(minAgo(1), [50, 50, 50, 50, 50], conns: 10),
      ], now);
      expect(s.ping.trend, 15);
      // Было (0.25·85 + 15 + 20) / 0.6 = 93.75 → 94, стало 100.
      expect(s.overall.trend, 6);
      expect(s.errorsFree.trend, 0, reason: 'вчера счётчиков не было');
    });
  });

  group('история по дням', () {
    test('30 дней, день без данных и минуты недоступности', () {
      final history = computeHistory([
        ...minute(DateTime(2025, 9, 4, 10), [50, 50, 50, 50, 50], conns: 1, errs: 1), // старше 30 дней
        ...minute(DateTime(2025, 10, 7, 10), [null, null, null, null, null]),
        ...minute(DateTime(2025, 10, 7, 10, 1), [null, null, null, null, null]),
        ...minute(DateTime(2025, 10, 7, 10, 2), [50, 50, 50, 50, 50], conns: 100, errs: 4),
        ...minute(DateTime(2025, 10, 9, 11), [50, 50, 50, 50, 50], conns: 100, errs: 2),
      ], now);

      expect(history, hasLength(30));
      expect(history.first.day, DateTime(2025, 9, 10));
      expect(history.last.day, DateTime(2025, 10, 9));
      expect(history.where((d) => d.score != null).map((d) => d.day), [DateTime(2025, 10, 7), DateTime(2025, 10, 9)]);

      final empty = history[28];
      expect(empty.day, DateTime(2025, 10, 8));
      expect((empty.score, empty.errors, empty.outageMinutes), (null, 0, 0));

      final bad = history[27];
      expect(bad.outageMinutes, 2);
      expect(bad.errors, 4);
      // Пинг 100, джиттер 100, потери 10 из 15 → 0, ошибки 96, DNS 100.
      expect(bad.score, 79);

      expect(history.last.errors, 2);
      expect(history.last.score, greaterThanOrEqualTo(healthGoodFrom));
    });

    test('без записей — 30 пустых дней', () {
      final history = computeHistory(const [], now);
      expect(history, hasLength(30));
      expect(history.every((d) => d.score == null && d.errors == 0 && d.outageMinutes == 0), isTrue);
    });
  });
}
