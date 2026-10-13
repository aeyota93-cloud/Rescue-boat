import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/compare/model/compare_models.dart';
import 'package:hiddify/features/compare/model/compare_target.dart';
import 'package:hiddify/features/servers/model/rescue_servers.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';

import '../servers/servers_fixtures.dart';

/// Ответ ядра v2: напрямую, vpn и три сервера.
CompareResult result({
  required List<int?> direct,
  required List<int?> nl,
  required List<int?> backup,
  required List<int?> games,
  bool estimate = false,
  bool done = true,
}) => CompareResult.tryParse({
  'v': 1,
  'id': 'roads0000001',
  'method': estimate ? 'icmp' : 'tls',
  'done': done,
  'paths': {
    'direct': {'available': true, 'samples': direct},
    'vpn': {'available': !estimate, 'samples': nl},
    'servers': [
      {'tag': 'NL', 'available': !estimate, 'samples': nl, if (estimate) 'estimate': true},
      {'tag': 'NL запасной', 'available': !estimate, 'samples': backup, if (estimate) 'estimate': true},
      {'tag': 'NL игры', 'available': !estimate, 'samples': games, if (estimate) 'estimate': true},
    ],
  },
})!;

List<int?> around(int ms) => [ms, ms + 1, ms - 1, ms + 2, ms, ms - 2, ms + 1, ms, ms - 1, ms];

void main() {
  final servers = rescueServersOf(threeServers(), threeServersOrder)!;
  String name(String tag) => servers.byTag(tag)!.lowerName;

  group('ответ v2', () {
    test('servers читаются по порядку, estimate без поля — false, замеры считаются по всем дорогам', () {
      final r = result(direct: [40, 41], nl: [90], backup: [100, null], games: [], done: false);
      expect([for (final s in r.servers) s.tag], ['NL', 'NL запасной', 'NL игры']);
      expect(r.servers.every((s) => !s.estimate), isTrue);
      expect(r.samplesDone, 2 + 1 + 1 + 2 + 0);
      expect(compareRoads(r).map((e) => e.id), [directRoad, 'NL', 'NL запасной', 'NL игры']);

      final old = CompareResult.tryParse({
        'id': 'old000000001',
        'paths': {
          'direct': {
            'samples': [1],
          },
          'vpn': {
            'samples': [2],
          },
        },
      })!;
      expect(old.servers, isEmpty);
      expect(compareRoads(old), isEmpty, reason: 'старое ядро — две дороги, как раньше');
      expect(roadVerdict(old, serverName: name), isNull);
    });
  });

  group('лучшая дорога', () {
    test('сравнение по правилу договора: неудачи, потом медиана, «одинаково»', () {
      expect(compareStats(PathStats.of(around(40)), PathStats.of(around(95))), -1);
      expect(compareStats(PathStats.of(around(95)), PathStats.of(around(40))), 1);
      expect(compareStats(PathStats.of(around(100)), PathStats.of(around(108))), 0, reason: '< 10 мс');
      expect(compareStats(PathStats.of(around(300)), PathStats.of(around(330))), 0, reason: '< 15 %');
      final flaky = [40, null, 40, null, 40, 40, 40, 40, 40, 40];
      expect(compareStats(PathStats.of(flaky), PathStats.of(around(95))), 1, reason: 'неудач на 20 п.п. больше');
      expect(compareStats(PathStats.of(const []), PathStats.of(around(95))), isNull);
    });

    test('лучше другой сервер — «на N мс быстрее, чем сейчас»', () {
      final r = result(direct: around(140), nl: around(95), backup: around(120), games: around(40));
      final v = roadVerdict(r, current: 'NL', serverName: name)!;
      expect(v.kind, RoadVerdictKind.change);
      expect(v.best, 'NL игры');
      expect(v.bestServer, 'NL игры');
      expect(v.text, 'Лучше через запасной 2: на 55 мс быстрее, чем сейчас');
    });

    test('лучше напрямую; кнопка сервера — лучший из серверов', () {
      final r = result(direct: around(20), nl: around(95), backup: around(60), games: around(140));
      final v = roadVerdict(r, current: 'NL', serverName: name)!;
      expect(v.best, directRoad);
      expect(v.bestServer, 'NL запасной');
      expect(v.text, 'Лучше напрямую: на 75 мс быстрее, чем сейчас');
    });

    test('несколько лидеров «одинаково» — лучшей считается текущая', () {
      final r = result(direct: around(140), nl: around(42), backup: around(40), games: around(41));
      final keep = roadVerdict(r, current: 'NL', serverName: name)!;
      expect(keep.kind, RoadVerdictKind.keep);
      expect(keep.best, 'NL');
      expect(keep.leaders, {'NL', 'NL запасной', 'NL игры'});
      expect(keep.text, 'Разницы почти нет — лучше оставить как есть');

      // «Сейчас» неизвестно (цели нет в списках) — берём лидера с меньшей медианой.
      final unknown = roadVerdict(r, serverName: name)!;
      expect(unknown.kind, RoadVerdictKind.change);
      expect(unknown.best, 'NL запасной');
      expect(unknown.text, 'Лучше через запасной 1');

      // Текущая — единственный лидер.
      final only = roadVerdict(
        result(direct: around(140), nl: around(40), backup: around(90), games: around(95)),
        current: 'NL',
        serverName: name,
      )!;
      expect(only.kind, RoadVerdictKind.keep);
      expect(only.text, 'Лучше всего — как сейчас, через основной');
    });

    test('решают неудачи: «сейчас чаще неудачи»', () {
      final flaky = [40, null, 40, null, 40, null, 40, 40, 40, 40];
      final r = result(direct: around(140), nl: flaky, backup: around(45), games: around(140));
      final v = roadVerdict(r, current: 'NL', serverName: name)!;
      expect(v.best, 'NL запасной');
      expect(v.text, 'Лучше через запасной 1: сейчас чаще неудачи (30 % против 0 %)');
    });

    test('игры по UDP: серверы по качеству туннеля, вывод с оговоркой', () {
      final r = result(direct: around(30), nl: around(90), backup: around(95), games: around(60), estimate: true);
      final v = roadVerdict(r, current: 'NL', serverName: name)!;
      expect(v.kind, RoadVerdictKind.estimate);
      expect(v.best, 'NL игры');
      expect(v.text, 'Для игры точно покажет только сама игра; по качеству дороги лучше всего — запасной 2');
    });

    test('пока замеры идут или ошибка — вывода нет', () {
      expect(
        roadVerdict(
          result(direct: [1], nl: [2], backup: [3], games: [4], done: false),
          serverName: name,
        ),
        isNull,
      );
    });
  });

  test('какой дорогой цель идёт сейчас', () {
    const item = (kind: SplitKind.domain, value: 'example.com');
    final onBackup = rescueServersOf(threeServers(selected: 'NL запасной'), threeServersOrder);
    expect(currentRoadOf(const SplitTunnel(), onBackup, item), isNull, reason: 'решают общие правила');
    expect(currentRoadOf(const SplitTunnel(bypass: SplitList(domains: ['example.com'])), onBackup, item), directRoad);
    expect(
      currentRoadOf(const SplitTunnel(via: SplitList(domains: ['example.com'])), onBackup, item),
      'NL запасной',
      reason: '«Авто» — куда смотрит select',
    );
    const pinned = SplitTunnel(
      servers: {
        'NL игры': SplitList(domains: ['example.com']),
      },
    );
    expect(currentRoadOf(pinned, onBackup, item), 'NL игры');
    const lost = SplitTunnel(
      servers: {
        'пропал': SplitList(domains: ['example.com']),
      },
    );
    expect(currentRoadOf(lost, onBackup, item), 'NL запасной', reason: 'сервера нет — идёт через «Авто»');
    expect(currentRoadOf(const SplitTunnel(via: SplitList(domains: ['example.com'])), null, item), isNull);
  });
}
