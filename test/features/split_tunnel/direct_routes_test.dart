import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/data/tun_routes.dart';
import 'package:hiddify/features/split_tunnel/model/direct_routes.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';

final _now = DateTime(2026, 11, 26, 22, 30);

V4Net n(String s) => V4Net.tryParse(s)!;

const _split = SplitTunnel(
  bypass: SplitList(apps: ['Overwatch.exe', 'Marvel-Win64-Shipping.exe', 'vivaldi.exe']),
  via: SplitList(apps: ['Discord.exe']),
);

NetConnection _conn({
  String exe = 'Overwatch.exe',
  String ip = '35.228.147.76',
  String port = '26538',
  String network = 'udp',
  String chain = 'direct §hide§',
  int download = 7000000,
}) => NetConnection(
  id: '1',
  exe: exe,
  host: '',
  ip: ip,
  port: port,
  network: network,
  viaVpn: !chain.startsWith('direct'),
  upload: 0,
  download: download,
  chains: [chain],
);

/// Таблица маршрутов в памяти: записывает порядок изменений.
class _FakeRoutes implements TunRoutes {
  _FakeRoutes(Iterable<V4Net> routes, {this.broken = false}) : routes = routes.toSet();

  final Set<V4Net> routes;
  final int index = 4;
  final bool broken;
  final log = <String>[];

  @override
  Future<({int index, List<V4Net> routes})?> read() async =>
      routes.isEmpty ? null : (index: index, routes: routes.toList());

  @override
  Future<void> change(int index, {required List<V4Net> add, required List<V4Net> remove}) async {
    for (final r in add) {
      log.add('+$r');
      routes.add(r);
    }
    for (final r in remove.take(broken ? remove.length - 1 : remove.length)) {
      log.add('-$r');
      routes.remove(r);
    }
  }
}

void main() {
  group('V4Net', () {
    test('parse, normalize, label', () {
      expect(n('5.42.160.7/20').toString(), '5.42.160.0/20');
      expect(n('35.228.147.76').toString(), '35.228.147.76/32');
      expect(n('35.228.147.76').label, '35.228.147.76');
      for (final bad in ['', '1.2.3', '1.2.3.256', '1.2.3.4/33', 'abc', '2a00::1', '1.2.3.4/']) {
        expect(V4Net.tryParse(bad), isNull, reason: bad);
      }
    });

    test('collapse and subtract', () {
      expect(collapseNets([n('10.0.0.0/25'), n('10.0.0.128/25')]), [n('10.0.0.0/24')]);
      expect(subtractNets([n('10.0.0.0/24')], [n('10.0.0.0/25')]), [n('10.0.0.128/25')]);
      expect(subtractNets([n('10.0.0.0/30')], [n('10.0.0.1')]), [n('10.0.0.0/32'), n('10.0.0.2/31')]);
      expect(subtractNets([n('10.0.0.0/24')], [n('9.0.0.0/8')]), [n('10.0.0.0/24')]);
    });

    test('tunnel routes are all IPv4 minus the list, like the core', () {
      expect(tunRouteRanges(const []), [V4Net(0, 0)]);
      final one = tunRouteRanges([n('35.228.147.76')]);
      expect(one.length, 32, reason: 'one address splits /0 into 32 prefixes');
      expect(one.any((r) => r.contains(n('35.228.147.76'))), isFalse);
      expect(one.where((r) => r.contains(n('35.228.147.77'))).length, 1);
      // Сети Blizzard: столько же маршрутов, сколько строит sing-tun (проверено в Python ipaddress).
      expect(tunRouteRanges(blizzardNets.map(n)).length, 322);
    });

    test('diff: add what is missing, remove what is extra', () {
      final d = tunRouteDiff([V4Net(0, 0)], tunRouteRanges([n('1.0.0.1')]));
      expect(d.add.length, 32);
      expect(d.remove, [V4Net(0, 0)]);
      final same = tunRouteDiff(d.add, tunRouteRanges([n('1.0.0.1')]));
      expect(same.add, isEmpty);
      expect(same.remove, isEmpty);
    });
  });

  test('parseDirectInput', () {
    expect(parseDirectInput('35.228.147.76').net, n('35.228.147.76'));
    expect(parseDirectInput(' 137.221.64.0/19 ').net, n('137.221.64.0/19'));
    expect(parseDirectInput('192.168.1.1').error, isNotNull);
    expect(parseDirectInput('1.0.0.0/7').error, contains('/8'));
    expect(parseDirectInput('example.com').error, isNotNull);
    expect(parseDirectInput('').net, isNull);
  });

  group('isGameFlow', () {
    test('a match of a bypass game counts', () {
      expect(isGameFlow(_conn(), _split), isTrue);
      expect(isGameFlow(_conn(exe: 'overwatch.exe'), _split), isTrue);
    });

    test('everything else does not', () {
      expect(isGameFlow(_conn(network: 'tcp'), _split), isFalse, reason: 'TCP: sites and CDN');
      expect(
        isGameFlow(_conn(port: '443', exe: 'vivaldi.exe'), _split),
        isFalse,
        reason: 'QUIC',
      );
      expect(isGameFlow(_conn(download: 2000), _split), isFalse, reason: 'ping probe');
      expect(
        isGameFlow(_conn(exe: 'Discord.exe', chain: 'Сервер 2'), _split),
        isFalse,
        reason: 'via VPN',
      );
      expect(isGameFlow(_conn(exe: 'Telegram.exe'), _split), isFalse, reason: 'not in bypass');
      expect(isGameFlow(_conn(exe: ''), _split), isFalse, reason: 'unknown program');
      expect(isGameFlow(_conn(ip: '192.168.1.1'), _split), isFalse, reason: 'home network');
      expect(isGameFlow(_conn(ip: '2a00:1450::1'), _split), isFalse, reason: 'IPv6');
    });
  });

  test('isGameError takes only direct UDP of bypass games', () {
    ErrorEvent e({String app = 'Marvel-Win64-Shipping.exe', String net = 'udp', int port = 5504}) => ErrorEvent(
      time: _now,
      kind: ErrorKind.values.first,
      app: app,
      ip: '35.234.90.158',
      port: port,
      network: net,
      route: ErrorRoute.direct,
    );
    expect(isGameError(e(), _split), isTrue);
    expect(isGameError(e(net: 'tcp'), _split), isFalse);
    expect(isGameError(e(port: 443), _split), isFalse);
    expect(isGameError(e(app: 'Battle.net.exe'), _split), isFalse);
  });

  group('DirectRoutes', () {
    test('learn: adds, keeps identity when nothing changes, forgets old but not pinned', () {
      final a = const DirectRoutes().learn([('35.228.147.76', 'Overwatch.exe', _now)], _now);
      expect(a.entries.keys, [n('35.228.147.76')]);
      final same = a.learn([('35.228.147.76', 'Overwatch.exe', _now.add(const Duration(minutes: 5)))], _now);
      expect(identical(same, a), isTrue, reason: 'refresh at most once an hour');
      final later = _now.add(learnedRoutesTtl + const Duration(days: 1));
      expect(a.learn(const [], later).entries, isEmpty);
      expect(a.withPinned(n('35.228.147.76'), true).learn(const [], later).entries, hasLength(1));
    });

    test('learn keeps only the newest learnedRoutesMax, own entries are not counted', () {
      final found = [
        for (var i = 0; i < learnedRoutesMax + 10; i++)
          ('35.228.${i ~/ 250}.${i % 250 + 1}', 'Overwatch.exe', _now.subtract(Duration(minutes: i))),
      ];
      final r = const DirectRoutes().withUser(n('1.1.1.1'), _now).learn(found, _now);
      expect(r.entries.values.where((e) => e.source == DirectSource.learned).length, learnedRoutesMax);
      expect(r.entries.containsKey(n('1.1.1.1')), isTrue);
      expect(r.entries.containsKey(n(found.last.$1)), isFalse);
    });

    test('never: removes the entry, blocks learning, cuts it out of Blizzard', () {
      var r = const DirectRoutes().learn([('35.228.147.76', 'Overwatch.exe', _now)], _now);
      r = r.withNever(n('35.228.147.76'));
      expect(r.entries, isEmpty);
      expect(r.learn([('35.228.147.76', 'Overwatch.exe', _now)], _now).entries, isEmpty);
      r = r.withNever(n('137.221.64.10'));
      final eff = r.effective(_split, enabled: true);
      expect(eff.any((x) => x.contains(n('137.221.64.10'))), isFalse);
      expect(eff.any((x) => x.contains(n('137.221.64.11'))), isTrue);
      // Добавить снова вручную — снимает запрет.
      expect(r.withUser(n('35.228.147.76'), _now).never, isNot(contains(n('35.228.147.76'))));
    });

    test('effective: own always, learned only while the game is in bypass, Blizzard by switch', () {
      final r = const DirectRoutes().withUser(n('8.8.4.4'), _now).learn([
        ('35.228.147.76', 'Overwatch.exe', _now),
        ('35.234.90.158', 'OldGame.exe', _now),
      ], _now);
      final eff = r.effective(_split, enabled: true);
      expect(eff, contains(n('8.8.4.4')));
      expect(eff, contains(n('35.228.147.76')));
      expect(eff, isNot(contains(n('35.234.90.158'))), reason: 'game left bypass');
      expect(eff.any((x) => x.contains(n('137.221.64.1'))), isTrue);
      expect(
        r.copyWith(blizzard: false).effective(_split, enabled: true).any((x) => x.contains(n('137.221.64.1'))),
        isFalse,
      );
      const noBlizzard = SplitTunnel(bypass: SplitList(apps: ['Marvel-Win64-Shipping.exe']));
      expect(r.effective(noBlizzard, enabled: true).any((x) => x.contains(n('137.221.64.1'))), isFalse);
      expect(r.effective(_split, enabled: false), isEmpty);
    });

    test('JSON round trip and the first version file', () {
      final r = const DirectRoutes()
          .withUser(n('8.8.4.4'), _now)
          .learn([('34.88.131.44', 'Overwatch.exe', _now)], _now)
          .withNever(n('1.2.3.4'))
          .copyWith(seeded: true, blizzard: false);
      final back = DirectRoutes.fromJson(r.toJson());
      expect(back.entries.keys.toSet(), {n('8.8.4.4'), n('34.88.131.44')});
      expect(back.entries[n('8.8.4.4')]!.source, DirectSource.user);
      expect(back.never, {n('1.2.3.4')});
      expect(back.seeded, isTrue);
      expect(back.blizzard, isFalse);

      final v1 = DirectRoutes.fromJson({
        'version': 1,
        'seeded': true,
        'routes': {
          '35.228.147.76': {'app': 'Overwatch.exe', 'last': _now.millisecondsSinceEpoch},
          '10.0.0.1': {'app': 'x.exe', 'last': 1},
          'bad': 'x',
        },
      });
      expect(v1.entries.keys, [n('35.228.147.76')]);
      expect(v1.entries.values.single.source, DirectSource.learned);
      expect(v1.blizzard, isTrue);
    });

    test('tun-exclude.txt lists the effective nets', () {
      final text = tunExcludeText([n('137.221.64.0/19'), n('35.228.147.76')]);
      expect(text, contains('137.221.64.0/19\n'));
      expect(text, contains('35.228.147.76/32\n'));
      expect(tunExcludeText(const []).split('\n').where((l) => l.isNotEmpty && !l.startsWith('#')), isEmpty);
    });
  });

  group('applyTunRoutes', () {
    test('adds new routes first, then removes old ones, and checks the result', () async {
      final fake = _FakeRoutes([V4Net(0, 0)]);
      final r = await applyTunRoutes(fake, [n('1.0.0.1')]);
      expect(r.added, 32);
      expect(r.removed, 1);
      expect(fake.log.first, startsWith('+'), reason: 'no moment without a tunnel route');
      expect(fake.log.last, '-0.0.0.0/0');
      expect(fake.routes, tunRouteRanges([n('1.0.0.1')]).toSet());
      // И обратно: адрес возвращается в Шлюпку.
      await applyTunRoutes(fake, const []);
      expect(fake.routes, {V4Net(0, 0)});
    });

    test('no tunnel — clear error, nothing changed', () async {
      final fake = _FakeRoutes(const []);
      await expectLater(applyTunRoutes(fake, [n('1.0.0.1')]), throwsA(isA<TunRoutesException>()));
      expect(fake.log, isEmpty);
    });

    test('partial change is reported', () async {
      final fake = _FakeRoutes([V4Net(0, 0)], broken: true);
      await expectLater(applyTunRoutes(fake, [n('1.0.0.1')]), throwsA(isA<TunRoutesException>()));
    });
  });
}
