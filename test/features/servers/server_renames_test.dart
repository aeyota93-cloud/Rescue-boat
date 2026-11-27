import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/servers/model/servers_format.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';

void main() {
  test('endpoints: type, address and port of each server, groups skipped', () {
    final e = endpointsOfConfig({
      'outbounds': [
        {'type': 'vless', 'tag': 'Сервер 2', 'server': '31.0.0.3', 'server_port': 443},
        {'type': 'vless', 'tag': 'Сервер 1 через РФ', 'server': '77.0.0.4', 'server_port': 2084},
        {
          'type': 'selector',
          'tag': 'select',
          'outbounds': ['Сервер 2'],
        },
        {'type': 'direct', 'tag': 'direct'},
      ],
      'endpoints': [
        {'type': 'awg', 'tag': 'AWG', 'peers': <Object>[]},
      ],
    });
    expect(e, {'Сервер 2': 'vless|31.0.0.3:443', 'Сервер 1 через РФ': 'vless|77.0.0.4:2084'});
  });

  test('renames: same address and port under one new name; doubtful cases left alone', () {
    const before = {
      'Сервер 2': 'vless|31.0.0.3:443',
      'Сервер 1': 'vless|130.0.0.1:2083',
      'Сервер 2 через РФ': 'vless|77.0.0.4:2087',
      'Старый': 'vless|1.1.1.1:443',
      'Двойник': 'vless|2.2.2.2:443',
    };
    const after = {
      'N': 'vless|31.0.0.3:443',
      'F': 'vless|130.0.0.1:2083',
      'РФ → N': 'vless|77.0.0.4:2087',
      // Двойнику два кандидата — не угадываем.
      'А': 'vless|2.2.2.2:443',
      'Б': 'vless|2.2.2.2:443',
    };
    expect(serverRenames(before, after), {'Сервер 2': 'N', 'Сервер 1': 'F', 'Сервер 2 через РФ': 'РФ → N'});
    expect(serverRenames(after, after), isEmpty, reason: 'nothing renamed');
    expect(serverRenames(const {'X': 'vless|9.9.9.9:1'}, after), isEmpty, reason: 'server is gone');
  });

  test('split tunnel: pins move to the new name, merged with what is already there', () {
    const s = SplitTunnel(
      servers: {
        'Сервер 1': SplitList(domains: ['gemini.google.com']),
        'Сервер 2': SplitList(apps: ['Discord.exe']),
        'N': SplitList(domains: ['youtube.com']),
      },
    );
    final r = s.withServersRenamed({'Сервер 1': 'F', 'Сервер 2': 'N'});
    expect(r.servers.keys.toSet(), {'F', 'N'});
    expect(r.serverOf(SplitKind.domain, 'gemini.google.com'), 'F');
    expect(r.serverOf(SplitKind.app, 'Discord.exe'), 'N');
    expect(r.serverOf(SplitKind.domain, 'youtube.com'), 'N');
    expect(s.withServersRenamed({'Нет такого': 'F'}).servers, s.servers);
  });
}
