import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/compare/model/compare_models.dart';
import 'package:hiddify/features/compare/model/compare_target.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';

CompareResult result(PathResult? direct, PathResult? vpn, {bool done = true, String error = ''}) =>
    CompareResult(id: 'abc12345', done: done, error: error, direct: direct, vpn: vpn);

PathResult path(List<int?> samples, {bool available = true, bool estimate = false, int? first, String note = ''}) =>
    PathResult(available: available, estimate: estimate, samples: samples, firstMs: first, note: note);

List<int?> same(int ms, [int n = 10]) => List.filled(n, ms);

NetConnection conn(String exe, {String host = '', String ip = '', String port = '443', String network = 'tcp'}) =>
    NetConnection(
      id: '$exe$host$ip$port$network${DateTime.now().microsecondsSinceEpoch}',
      exe: exe,
      host: host,
      ip: ip,
      port: port,
      network: network,
      viaVpn: true,
      upload: 0,
      download: 0,
    );

void main() {
  group('цифры по замерам', () {
    test('медиана без неудач, разброс по соседним, доля неудач', () {
      final s = PathStats.of([41, 40, null, 43]);
      expect(s.median, 41);
      expect(s.jitter, 2.0, reason: '(|40-41| + |43-40|) / 2, неудача не в счёт');
      expect(s.failed, 1);
      expect(s.total, 4);
      expect(s.failPercent, 25);
    });

    test('чётное число замеров — среднее двух средних, округлённое', () {
      expect(PathStats.of([10, 20, 30, 41]).median, 25);
      expect(PathStats.of([40, 41]).median, 41);
    });

    test('пусто и одни неудачи', () {
      final none = PathStats.of(const []);
      expect((none.median, none.jitter, none.failPercent), (null, null, null));
      final fail = PathStats.of([null, null]);
      expect((fail.median, fail.jitter, fail.failPercent), (null, null, 100));
      expect(PathStats.of([50]).jitter, isNull, reason: 'один замер — разброса нет');
    });

    test('«41 мс» и «1,2 с»', () {
      expect(formatMs(41), '41 мс');
      expect(formatMs(999.6), '1 с');
      expect(formatMs(1200), '1,2 с');
      expect(formatMs(2000), '2 с');
    });
  });

  group('вывод', () {
    // (название, напрямую, через VPN, вид, текст)
    final cases = <(String, PathResult, PathResult, VerdictKind, String)>[
      (
        'напрямую быстрее на 45',
        path(same(40)),
        path(same(85)),
        VerdictKind.direct,
        'Лучше напрямую: на 45 мс быстрее',
      ),
      (
        'через VPN быстрее на 40',
        path(same(100)),
        path(same(60)),
        VerdictKind.vpn,
        'Лучше через VPN: на 40 мс быстрее',
      ),
      ('разница 10 мс и 10 % — одинаково', path(same(100)), path(same(110)), VerdictKind.same, 'Разницы почти нет'),
      ('мелкие значения: < 10 мс — одинаково', path(same(5)), path(same(14)), VerdictKind.same, 'Разницы почти нет'),
      (
        'ровно 15 мс при 15 % — уже разница',
        path(same(100)),
        path(same(115)),
        VerdictKind.direct,
        'Лучше напрямую: на 15 мс быстрее',
      ),
      ('большие значения: 14 % — одинаково', path(same(500)), path(same(570)), VerdictKind.same, 'Разницы почти нет'),
      (
        'неудачи ровно на 10 п.п. — хуже, хотя медиана лучше',
        path(same(40)),
        path([...same(30, 9), null]),
        VerdictKind.direct,
        'Лучше напрямую: через VPN чаще неудачи (10 % против 0 %)',
      ),
      (
        'неудачи на 9 п.п. не считаются, решает медиана',
        path(same(40, 11)),
        path([...same(30), null]),
        VerdictKind.vpn,
        'Лучше через VPN: на 10 мс быстрее',
      ),
      (
        'напрямую чаще неудачи',
        path([...same(40, 8), null, null]),
        path(same(90)),
        VerdictKind.vpn,
        'Лучше через VPN: напрямую чаще неудачи (20 % против 0 %)',
      ),
      (
        'через VPN ни одного ответа',
        path(same(40)),
        path(List<int?>.filled(10, null)),
        VerdictKind.direct,
        'Лучше напрямую: через VPN чаще неудачи (100 % против 0 %)',
      ),
      (
        'null не мешают медиане: 41 против 41',
        path([41, 40, null, 43]),
        path([40, 41, null, 43]),
        VerdictKind.same,
        'Разницы почти нет',
      ),
      (
        'обе дороги молчат',
        path(List<int?>.filled(5, null)),
        path(List<int?>.filled(5, null)),
        VerdictKind.noData,
        'Ни одна дорога не ответила. Проверьте адрес',
      ),
      (
        'игры по UDP: только оценка туннеля',
        path(same(41, 3)),
        path(same(95, 3), available: false, estimate: true, note: 'через VPN измерить нельзя'),
        VerdictKind.notComparable,
        'Для игр по UDP сравнить нельзя. Прямой путь: 41 мс.',
      ),
      (
        'игры по UDP: прямой путь молчит',
        path(List<int?>.filled(3, null)),
        path(same(95, 3), available: false, estimate: true),
        VerdictKind.notComparable,
        'Для игр по UDP сравнить нельзя. Прямой путь не ответил.',
      ),
      (
        'через VPN измерить нельзя без оценки',
        path(same(40)),
        path(const [], available: false),
        VerdictKind.noData,
        'Сравнить не удалось: измерить нельзя — через VPN',
      ),
      ('замеров нет', path(const []), path(same(40)), VerdictKind.noData, 'Сравнить не удалось: замеров нет'),
    ];

    for (final (name, direct, vpn, kind, text) in cases) {
      test(name, () {
        final v = compareVerdict(result(direct, vpn))!;
        expect(v.kind, kind);
        expect(v.text, text);
      });
    }

    test('пока замеры идут или была ошибка — вывода нет', () {
      expect(compareVerdict(result(path(same(40)), path(same(80)), done: false)), isNull);
      expect(compareVerdict(result(null, null, error: 'не резолвится домен')), isNull);
    });

    test('в ответе нет одной из дорог', () {
      final v = compareVerdict(result(path(same(40)), null))!;
      expect(v.kind, VerdictKind.noData);
    });

    test('разница в мс записана', () {
      expect(compareVerdict(result(path(same(40)), path(same(85))))!.diffMs, 45);
      expect(compareVerdict(result(path(same(100)), path(same(110))))!.diffMs, 0);
    });
  });

  group('ответ ядра', () {
    test('разбор частичного и итогового ответа, null в samples', () {
      final r = CompareResult.tryParse({
        'v': 1,
        'id': 'k3j9x0a1',
        'target': 'www.example.com',
        'ip': '93.184.216.34',
        'method': 'tls',
        'done': false,
        'error': '',
        'paths': {
          'direct': {
            'available': true,
            'first_ms': 120,
            'samples': [41, 40, null, 43],
            'note': '',
          },
          'vpn': {
            'available': true,
            'first_ms': 380,
            'samples': [95, 97],
            'note': '',
          },
        },
      })!;
      expect(r.done, isFalse);
      expect(r.ip, '93.184.216.34');
      expect(r.direct!.samples, [41, 40, null, 43]);
      expect(r.direct!.firstMs, 120);
      expect(r.samplesDone, 6);
    });

    test('мусор и чужие формы не падают', () {
      expect(CompareResult.tryParse('текст'), isNull);
      expect(CompareResult.tryParse({'v': 1}), isNull);
      final r = CompareResult.tryParse({
        'id': 'x1234567',
        'paths': {
          'direct': {'samples': 'не список', 'first_ms': 'x'},
        },
      })!;
      expect(r.direct!.samples, isEmpty);
      expect(r.direct!.firstMs, isNull);
      expect(r.vpn, isNull);
    });

    test('estimate читается', () {
      final r = CompareResult.tryParse({
        'id': 'x1234567',
        'paths': {
          'vpn': {
            'available': false,
            'estimate': true,
            'samples': [90],
            'note': 'через VPN измерить нельзя',
          },
        },
      })!;
      expect(r.vpn!.estimate, isTrue);
      expect(r.vpn!.available, isFalse);
      expect(r.vpn!.note, 'через VPN измерить нельзя');
    });
  });

  group('адрес', () {
    final cases = <String, (String, int)?>{
      'example.com': ('example.com', 443),
      '  HTTPS://www.Example.com/путь?x=1#y ': ('www.example.com', 443),
      'example.com:8443': ('example.com', 8443),
      'user:pass@example.com/x': ('example.com', 443),
      '8.8.8.8': ('8.8.8.8', 443),
      '8.8.8.8:53': ('8.8.8.8', 53),
      '[2001:db8::1]:8443': ('2001:db8::1', 8443),
      '2001:DB8::1': ('2001:db8::1', 443),
      'госуслуги.рф': ('xn--c1aapkosapc.xn--p1ai', 443),
      'localhost': null,
      '300.1.1.1': null,
      'example.com:99999': null,
      'a..b.com': null,
      '': null,
      '   ': null,
      'пример текст.рф!': null,
    };
    for (final MapEntry(key: input, value: expected) in cases.entries) {
      test('«$input»', () {
        final e = parseCompareTarget(input);
        if (expected == null) {
          expect(e, isNull);
        } else {
          expect((e!.host, e.port), expected);
        }
      });
    }

    test('запись для списков: программа — сама программа, IP — /32, сайт без www', () {
      const app = CompareSubject(endpoints: [CompareEndpoint('a.com')], appExe: 'chrome.exe');
      expect(compareSplitItem(app, const CompareEndpoint('a.com')), (kind: SplitKind.app, value: 'chrome.exe'));
      const plain = CompareSubject();
      expect(compareSplitItem(plain, const CompareEndpoint('8.8.8.8')), (kind: SplitKind.ip, value: '8.8.8.8/32'));
      expect(compareSplitItem(plain, const CompareEndpoint('2001:db8::1')), (
        kind: SplitKind.ip,
        value: '2001:db8::1/128',
      ));
      expect(compareSplitItem(plain, const CompareEndpoint('www.example.com')), (
        kind: SplitKind.domain,
        value: 'example.com',
      ));
    });
  });

  group('цели программы', () {
    test('сайт или IP, топ по числу соединений, домашние сети пропущены', () {
      final all = [
        for (var i = 0; i < 3; i++) conn('chrome.exe', host: 'a.com'),
        for (var i = 0; i < 2; i++) conn('Chrome.exe', host: 'B.com', port: '8443'),
        conn('chrome.exe', ip: '1.1.1.1', network: 'udp', port: '27015'),
        conn('chrome.exe', ip: '192.168.0.5'),
        conn('chrome.exe', ip: '127.0.0.1'),
        conn('chrome.exe'),
        conn('firefox.exe', host: 'other.com'),
      ];
      final eps = endpointsForApp('chrome.exe', all);
      expect(eps, [
        const CompareEndpoint('a.com'),
        const CompareEndpoint('b.com', 8443),
        const CompareEndpoint('1.1.1.1'),
      ]);
    });

    test('не больше пяти', () {
      final all = [for (var i = 0; i < 9; i++) conn('x.exe', host: 'site$i.com')];
      expect(endpointsForApp('x.exe', all), hasLength(5));
      expect(endpointsForApp('нет.exe', all), isEmpty);
    });
  });
}
