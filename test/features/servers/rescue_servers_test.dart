import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/servers/model/rescue_servers.dart';
import 'package:hiddify/features/servers/model/servers_format.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';

import '../screens_test_helpers.dart';
import 'servers_fixtures.dart';

const order = threeServersOrder;

void main() {
  group('ключ сервера', () {
    test('первые 12 hex sha256 от UTF-8 тега — как в ядре', () {
      expect(serverKey('NL запасной'), 'b286f8a79b8f');
      expect(serverKey('NL'), '4334ffcf7813');
      expect(serverKey('NL игры'), 'fdf34b41f62e');
      expect(serverKey('NL запасной'), matches(RegExp(r'^[0-9a-f]{12}$')));
    });
  });

  group('имена', () {
    test('протокол из конфига подписки: Reality и XHTTP различаются по транспорту; имя с протоколом', () {
      final protocols = protocolsOfConfig({
        'outbounds': [
          {'tag': 'proxy', 'type': 'selector'},
          {'tag': 'Best Latency', 'type': 'urltest'},
          {'tag': 'direct', 'type': 'direct'},
          {
            'tag': 'NL',
            'type': 'vless',
            'tls': {
              'reality': {'enabled': true},
            },
          },
          {
            'tag': 'NL запасной',
            'type': 'vless',
            'transport': {'type': 'xhttp'},
            'tls': {
              'reality': {'enabled': true},
            },
          },
          {
            'tag': 'NL игры',
            'type': 'hysteria2',
            'server_port': 443,
            'server_ports': ['20000:20999'],
          },
          {
            'tag': 'NL 8443',
            'type': 'vless',
            'server_port': 8443,
            'tls': {
              'reality': {'enabled': true},
            },
          },
          {
            'tag': 'старый',
            'type': 'vmess',
            'transport': {'type': 'ws'},
          },
        ],
      });
      expect(protocols, {
        'NL': 'VLESS Reality',
        'NL запасной': 'XHTTP',
        'NL игры': 'Hysteria2',
        'NL 8443': 'VLESS Reality (порт 8443)',
        'старый': 'VMess WebSocket',
      });
      final s = rescueServersOf(threeServers(), order)!.withProtocols(protocols);
      // Имя — из подписки без флага; протокол и роль — мелкой строкой.
      expect([for (final x in s.servers) x.name], ['NL', 'NL запасной', 'NL игры']);
      expect([for (final x in s.servers) x.role], ['Основной', 'Запасной 1', 'Запасной 2']);
      expect(
        [for (final x in s.servers) x.detail],
        ['VLESS Reality · основной', 'XHTTP · запасной 1', 'Hysteria2 · запасной 2'],
      );
      expect(serverPlaceLabel('NL игры', s), 'через NL игры');
      // Протокол переживает перезапуск.
      expect(RescueServers.decode(s.encode())!.servers.last.detail, 'Hysteria2 · запасной 2');
    });

    test('шесть дорог одного протокола различаются именами из подписки', () {
      final protocols = {for (final n in sixNames) n: 'VLESS gRPC Reality'};
      final s = rescueServersOf(sixServers())!.withProtocols(protocols);
      expect([for (final x in s.servers) x.name], sixNames);
      expect(s.servers.map((x) => x.name).toSet(), hasLength(6));
      expect(s.servers[4].detail, 'VLESS gRPC Reality · запасной 4');
      expect(s.servers[0].detail, 'VLESS gRPC Reality · основной');
      expect(serverPlaceLabel('Сервер 1 через РФ', s), 'через Сервер 1 через РФ');
      // Протокол неизвестен — мелкая строка только с ролью, имя то же.
      final bare = rescueServersOf(sixServers())!;
      expect(bare.servers[2].name, 'Сервер 2 через РФ');
      expect(bare.servers[2].detail, 'запасной 2');
      // Имя без флага и без remark — по тегу.
      expect(const RescueServer(tag: '🇳🇱 Сервер 9', index: 0).name, 'Сервер 9');
    });

    test('по порядку подписки, а не по пингу; группы не считаются', () {
      final s = rescueServersOf(threeServers(), order)!;
      expect([for (final x in s.servers) x.tag], ['NL', 'NL запасной', 'NL игры']);
      expect([for (final x in s.servers) x.name], ['NL', 'NL запасной', 'NL игры']);
      expect(s.servers[1].title, 'NL запасной');
      expect(s.group, 'select');
      expect(s.several, isTrue);
      expect(s.responding, 2);
      expect(s.onBackup, isFalse);
      expect(rescueServersOf(threeServers(selected: 'NL игры'), order)!.current!.name, 'NL игры');
      expect(rescueServersOf(threeServers(selected: 'balance'), order)!.current, isNull);
      expect(rescueServersOf(null), isNull);
    });

    test('сервер соединения по цепочке clash API (первый элемент — настоящий выход)', () {
      final s = rescueServersOf(threeServers(), order)!;
      expect(s.serverOfChain(['NL запасной', 'select'])!.name, 'NL запасной');
      expect(s.serverOfChain(['NL игры'])!.name, 'NL игры');
      expect(s.serverOfChain(['select', 'NL']), isNotNull, reason: 'порядок цепочки не важен');
      expect(s.serverOfChain(['direct']), isNull);
    });

    test('список на потом: только имена, без пинга и выбора', () {
      final s = rescueServersOf(threeServers(), order)!;
      final back = RescueServers.decode(s.encode())!;
      expect(back.live, isFalse);
      expect([for (final x in back.servers) x.name], ['NL', 'NL запасной', 'NL игры']);
      expect(back.servers[2].role, 'Запасной 2');
      expect(RescueServers.decode('битое'), isNull);
      expect(RescueServers.decode(null), isNull);
    });
  });

  group('модель туннеля с серверами', () {
    test('json туда-обратно; старый файл без servers читается', () {
      const s = SplitTunnel(
        via: SplitList(domains: ['youtube.com']),
        servers: {
          'NL игры': SplitList(apps: ['cs2.exe']),
        },
      );
      final back = SplitTunnel.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.servers.keys, ['NL игры']);
      expect(back.servers['NL игры']!.apps, ['cs2.exe']);
      expect(back.via.domains, ['youtube.com']);

      final old = SplitTunnel.fromJson({
        'bypass': {
          'apps': ['steam.exe'],
          'domains': <String>[],
          'ips': <String>[],
        },
        'via': {
          'apps': <String>[],
          'domains': ['x.com'],
          'ips': <String>[],
        },
      });
      expect(old.servers, isEmpty);
      expect(old.via.domains, ['x.com']);
      expect(old.bypass.apps, ['steam.exe']);
    });

    test('запись только в одном месте', () {
      var s = const SplitTunnel(bypass: SplitList(apps: ['cs2.exe']));
      s = s.placed(SplitKind.app, 'CS2.exe', SplitTarget.via, server: 'NL игры');
      expect(s.bypass.apps, isEmpty);
      expect(s.serverOf(SplitKind.app, 'cs2.exe'), 'NL игры');
      expect(s.targetOf(SplitKind.app, 'cs2.exe'), SplitTarget.via);

      s = s.placed(SplitKind.app, 'cs2.exe', SplitTarget.via, server: 'NL');
      expect(s.servers.keys, ['NL'], reason: 'пустой список сервера не хранится');

      s = s.placed(SplitKind.app, 'cs2.exe', SplitTarget.via);
      expect(s.servers, isEmpty);
      expect(s.via.apps, ['cs2.exe']);
      expect(s.serverOf(SplitKind.app, 'cs2.exe'), isNull);

      s = s.placed(SplitKind.app, 'cs2.exe', SplitTarget.via, server: 'NL').without(SplitKind.app, 'cs2.exe');
      expect(s.targetOf(SplitKind.app, 'cs2.exe'), isNull);
      expect(s.servers, isEmpty);
    });

    test('via-vpn = «Авто» ∪ все серверные пункты, без повторов', () {
      const s = SplitTunnel(
        via: SplitList(domains: ['youtube.com']),
        servers: {
          'NL игры': SplitList(apps: ['cs2.exe'], domains: ['YouTube.com']),
          'NL запасной': SplitList(ips: ['8.8.8.8/32']),
        },
      );
      final all = s.viaAll;
      expect(all.domains, ['youtube.com']);
      expect(all.apps, ['cs2.exe']);
      expect(all.ips, ['8.8.8.8/32']);
    });
  });

  group('файлы для ядра', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('split_servers_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Map<String, dynamic> read(String name) =>
        jsonDecode(File('${dir.path}/split/$name').readAsStringSync()) as Map<String, dynamic>;

    test('via-server-<key>.json у сервера с пунктами; убрали — файл пустой; via-vpn — всё вместе', () async {
      final container = await screensContainer(dir);
      addTearDown(container.dispose);
      final notifier = container.read(splitTunnelProvider.notifier);
      notifier.removeEverywhere(SplitKind.app, defaultBypassApps);
      notifier.addToServer('NL игры', SplitKind.app, 'cs2.exe');
      notifier.addToServer('NL запасной', SplitKind.domain, 'youtube.com');
      notifier.add(SplitTarget.via, SplitKind.domain, 'x.com');

      final games = viaServerFile(serverKey('NL игры'));
      final backup = viaServerFile(serverKey('NL запасной'));
      expect(backup, 'via-server-b286f8a79b8f.json');
      expect(read(games)['rules'], [
        {
          'process_path_regex': [processPathRegex('cs2.exe')],
        },
      ]);
      expect(read(backup)['rules'], [
        {
          'domain_suffix': ['youtube.com'],
        },
      ]);
      final vpn = read('via-vpn.json')['rules'] as List;
      expect(vpn, hasLength(2));
      expect(read('via-domains.json')['rules'], [
        {
          'domain_suffix': ['x.com', 'youtube.com'],
        },
      ]);

      // Пункт ушёл с сервера — файл остаётся, но пустой (ядро перечитает и снимет правило).
      notifier.add(SplitTarget.bypass, SplitKind.app, 'cs2.exe');
      expect(read(games), {'version': 3, 'rules': <Object>[]});
      expect(read('via-vpn.json')['rules'], [
        {
          'domain_suffix': ['x.com', 'youtube.com'],
        },
      ]);
      expect(container.read(splitTunnelProvider).servers.keys, ['NL запасной']);

      final saved = jsonDecode(File('${dir.path}/split-tunnel.json').readAsStringSync()) as Map<String, dynamic>;
      expect((saved['servers'] as Map).keys, ['NL запасной']);
    });
  });
}
