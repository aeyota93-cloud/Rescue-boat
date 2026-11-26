import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/model/game_routes.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';

final _now = DateTime(2026, 11, 26, 22, 30);

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

void main() {
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

  group('GameRoutes.learn', () {
    test('adds, keeps identity when nothing changes, forgets old', () {
      final a = const GameRoutes().learn([('35.228.147.76', 'Overwatch.exe', _now)], _now);
      expect(a.routes.keys, ['35.228.147.76']);
      final same = a.learn([('35.228.147.76', 'Overwatch.exe', _now.add(const Duration(minutes: 5)))], _now);
      expect(identical(same, a), isTrue, reason: 'refresh at most once an hour');
      final later = _now.add(gameRoutesTtl + const Duration(days: 1));
      expect(a.learn(const [], later).routes, isEmpty);
    });

    test('keeps only the newest gameRoutesMax', () {
      final found = [
        for (var i = 0; i < gameRoutesMax + 10; i++)
          ('35.228.${i ~/ 250}.${i % 250 + 1}', 'Overwatch.exe', _now.subtract(Duration(minutes: i))),
      ];
      final r = const GameRoutes().learn(found, _now);
      expect(r.routes.length, gameRoutesMax);
      expect(r.routes.containsKey('35.228.0.1'), isTrue);
      expect(r.routes.containsKey(found.last.$1), isFalse);
    });

    test('survives JSON and drops junk', () {
      final r = const GameRoutes().learn([('34.88.131.44', 'Overwatch.exe', _now)], _now).copyWith(seeded: true);
      final back = GameRoutes.fromJson({
        ...r.toJson(),
        'routes': {
          ...(r.toJson()['routes'] as Map),
          '10.0.0.1': {'app': 'x.exe', 'last': 1},
          'bad': 'x',
        },
      });
      expect(back.seeded, isTrue);
      expect(back.routes.keys, ['34.88.131.44']);
      expect(back.routes['34.88.131.44']!.lastSeen, _now);
    });
  });

  group('tunExcludeText', () {
    final routes = const GameRoutes().learn([
      ('35.228.147.76', 'Overwatch.exe', _now),
      ('8.8.4.4', 'OldGame.exe', _now), // игру убрали из «мимо VPN» — адрес не пишем
    ], _now);

    test('Blizzard nets and learned addresses of bypass games', () {
      final text = tunExcludeText(routes, _split, enabled: true);
      expect(text, contains('137.221.64.0/19'));
      expect(text, contains('35.228.147.76 # Overwatch.exe'));
      expect(text, isNot(contains('8.8.4.4')));
    });

    test('no Blizzard apps — no Blizzard nets; off — empty', () {
      const noBlizzard = SplitTunnel(bypass: SplitList(apps: ['Marvel-Win64-Shipping.exe']));
      expect(tunExcludeText(routes, noBlizzard, enabled: true), isNot(contains('137.221.')));
      final off = tunExcludeText(routes, _split, enabled: false);
      expect(off.split('\n').where((l) => l.isNotEmpty && !l.startsWith('#')), isEmpty);
    });
  });
}
