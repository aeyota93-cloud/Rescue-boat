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
          {'tag': 'NL игры', 'type': 'hysteria2'},
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
        'старый': 'VMess WebSocket',
      });
      final s = rescueServersOf(threeServers(), order)!.withProtocols(protocols);
      // Имя — протокол, роль — отдельно; в середине фразы регистр протокола не меняется.
      expect([for (final x in s.servers) x.name], ['VLESS Reality', 'XHTTP', 'Hysteria2']);
      expect([for (final x in s.servers) x.role], ['Основной', 'Запасной 1', 'Запасной 2']);
      expect(serverPlaceLabel('NL игры', s), 'через Hysteria2');
      expect(s.servers[1].nameWithRole, 'XHTTP (запасной 1)');
      // Протокол переживает перезапуск.
      expect(RescueServers.decode(s.encode())!.servers.last.name, 'Hysteria2');

      // Два сервера с одним протоколом — к имени добавляется роль; без протокола — роль.
      final same = rescueServersOf(threeServers(), order)!.withProtocols({'NL': 'XHTTP', 'NL запасной': 'XHTTP'});
      expect([for (final x in same.servers) x.name], ['XHTTP · основной', 'XHTTP · запасной 1', 'Запасной 2']);
      expect(same.servers.last.lowerName, 'запасной 2');
    });

    test('по порядку подписки, а не по пингу; группы не считаются; подсказки по типу', () {
      final s = rescueServersOf(threeServers(), order)!;
      expect([for (final x in s.servers) x.tag], ['NL', 'NL запасной', 'NL игры']);
      expect([for (final x in s.servers) x.name], ['Основной', 'Запасной 1', 'Запасной 2']);
      expect([for (final x in s.servers) x.hint], [null, 'если основной заблокируют', 'для игр и звонков']);
      expect(s.servers[1].lowerName, 'запасной 1');
      expect(s.servers[1].title, 'NL запасной');
      expect(s.group, 'select');
      expect(s.several, isTrue);
      expect(s.responding, 2);
      expect(s.onBackup, isFalse);
      expect(rescueServersOf(threeServers(selected: 'NL игры'), order)!.current!.name, 'Запасной 2');
      expect(rescueServersOf(threeServers(selected: 'balance'), order)!.current, isNull);
      expect(rescueServersOf(null), isNull);
      expect(serverHint('tuic', 0), 'для игр и звонков');
    });

    test('сервер соединения по цепочке clash API (первый элемент — настоящий выход)', () {
      final s = rescueServersOf(threeServers(), order)!;
      expect(s.serverOfChain(['NL запасной', 'select'])!.name, 'Запасной 1');
      expect(s.serverOfChain(['NL игры'])!.name, 'Запасной 2');
      expect(s.serverOfChain(['select', 'NL']), isNotNull, reason: 'порядок цепочки не важен');
      expect(s.serverOfChain(['direct']), isNull);
    });

    test('список на потом: только имена, без пинга и выбора', () {
      final s = rescueServersOf(threeServers(), order)!;
      final back = RescueServers.decode(s.encode())!;
      expect(back.live, isFalse);
      expect([for (final x in back.servers) x.name], ['Основной', 'Запасной 1', 'Запасной 2']);
      expect(back.servers[2].hint, 'для игр и звонков');
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
