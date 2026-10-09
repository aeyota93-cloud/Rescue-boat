import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/insights/data/error_groups.dart';
import 'package:hiddify/features/insights/data/stats_reader.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';

/// Время из образцов (errors-sample.jsonl): самая новая целая запись.
final t0 = DateTime.fromMillisecondsSinceEpoch(1760030463000);

String sample(String name) => File('test/features/insights/samples/$name').readAsStringSync();

void main() {
  late Directory dir;
  late StatsReader reader;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('insights_');
    reader = StatsReader(dir.path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  File statsFile(String prefix, DateTime day) => File('${dir.path}/${statsFileName(prefix, day)}');

  test('имя файла по местной дате', () {
    expect(statsFileName('errors', DateTime(2025, 1, 5, 23, 59)), 'errors-20250105.jsonl');
    expect(statsDays(DateTime(2025, 2, 27, 22), DateTime(2025, 3, 1, 1)), [
      DateTime(2025, 2, 27),
      DateTime(2025, 2, 28),
      DateTime(2025, 3),
    ]);
  });

  group('errors-*.jsonl', () {
    setUp(() => statsFile('errors', t0).writeAsStringSync(sample('errors-sample.jsonl')));

    test('битые строки и недописанный хвост пропускаются, неизвестные поля не мешают', () async {
      final events = await reader.errors(t0.subtract(const Duration(days: 1)), t0.add(const Duration(minutes: 1)));
      expect(events, hasLength(7));
      final discord = events.firstWhere((e) => e.time.millisecondsSinceEpoch == 1760030403000);
      expect(discord.kind, ErrorKind.other);
      expect(discord.route, ErrorRoute.vpn);
      expect(discord.count, 2);
      final stall = events.firstWhere((e) => e.kind == ErrorKind.stall);
      expect(stall.gapMs, 2300);
      expect(stall.network, 'udp');
      expect(stall.target, 'gateway.discord.gg');
      final steam = events.firstWhere((e) => e.app == 'steam.exe');
      expect(steam.count, 1, reason: 'нет n — одно событие');
      expect(steam.target, '23.62.214.9:443');
    });

    test('n учитывается в счётчике, «часть пропущена» тоже', () async {
      final events = await reader.errors(t0.subtract(const Duration(hours: 1)), t0);
      expect(events, hasLength(6), reason: 'DNS-ошибка старше часа');
      expect(countErrors(events), 1 + 3 + 1 + 2 + 1 + 42);
    });

    test('фильтр по периоду', () async {
      final lastMinutes = await reader.errors(t0.subtract(const Duration(seconds: 59)), t0);
      expect(lastMinutes.map((e) => e.kind), unorderedEquals([ErrorKind.reset, ErrorKind.suppressed]));
    });

    test('читаются только файлы нужных дней', () async {
      // Подложим в файл трёхдневной давности запись со «свежим» временем: её не должно быть видно.
      statsFile(
        'errors',
        t0.subtract(const Duration(days: 3)),
      ).writeAsStringSync('{"v":1,"t":${t0.millisecondsSinceEpoch},"kind":"refused","host":"old-file.example"}\n');
      final events = await reader.errors(t0.subtract(const Duration(hours: 1)), t0);
      expect(events.where((e) => e.host == 'old-file.example'), isEmpty);
    });

    test('нет папки или файла — пустой список', () async {
      expect(await StatsReader('${dir.path}/missing').errors(t0.subtract(const Duration(days: 7)), t0), isEmpty);
    });
  });

  group('quality-*.jsonl', () {
    test('замеры и счётчики, неизвестный type и битые строки пропускаются', () async {
      statsFile('quality', t0).writeAsStringSync(sample('quality-sample.jsonl'));
      final records = await reader.quality(t0.subtract(const Duration(hours: 1)), t0.add(const Duration(hours: 1)));
      final probes = records.whereType<QualityProbe>().toList();
      final counters = records.whereType<QualityCounters>().toList();
      expect(probes, hasLength(3));
      expect(probes.first.samples, [48, 51, null, 47, 49]);
      expect(probes.where((p) => p.isVpn), hasLength(2));
      expect(counters, hasLength(2));
      expect(counters.first.conns, 143);
      expect(counters.first.dnsOk, 88);
    });
  });

  group('дочитывание', () {
    String line(int i) => '{"v":1,"t":${t0.millisecondsSinceEpoch + i},"kind":"timeout","host":"h$i.example"}';
    final from = t0.subtract(const Duration(hours: 1));
    final to = t0.add(const Duration(hours: 1));

    test('новые строки дочитываются, недописанная появляется, когда допишется', () async {
      final f = statsFile('errors', t0)..writeAsStringSync('${line(1)}\n${line(2)}\n');
      expect(await reader.errors(from, to), hasLength(2));

      final third = line(3);
      f.writeAsStringSync(third.substring(0, 20), mode: FileMode.append);
      expect(await reader.errors(from, to), hasLength(2));

      f.writeAsStringSync('${third.substring(20)}\n', mode: FileMode.append);
      expect((await reader.errors(from, to)).map((e) => e.host), ['h1.example', 'h2.example', 'h3.example']);

      // Целая последняя строка без перевода строки тоже засчитывается.
      f.writeAsStringSync(line(4), mode: FileMode.append);
      expect(await reader.errors(from, to), hasLength(4));
      f.writeAsStringSync('\n${line(5)}\n', mode: FileMode.append);
      expect(await reader.errors(from, to), hasLength(5));
    });

    test('файл стал короче — читается с начала', () async {
      final f = statsFile('errors', t0)..writeAsStringSync('${line(1)}\n${line(2)}\n');
      expect(await reader.errors(from, to), hasLength(2));
      f.writeAsStringSync('${line(7)}\n');
      expect((await reader.errors(from, to)).single.host, 'h7.example');
    });

    test('одновременные чтения не задваивают записи', () async {
      statsFile('errors', t0).writeAsStringSync('${line(1)}\n${line(2)}\n');
      final results = await Future.wait([reader.errors(from, to), reader.errors(from, to)]);
      expect(results.map((r) => r.length), [2, 2]);
    });
  });
}
