import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';

void main() {
  group('parseSplitItem', () {
    final cases = <String, ({SplitKind kind, String value})?>{
      'youtube.com': (kind: SplitKind.domain, value: 'youtube.com'),
      '  YouTube.COM ': (kind: SplitKind.domain, value: 'youtube.com'),
      'https://www.example.com/page?x=1': (kind: SplitKind.domain, value: 'www.example.com'),
      '*.googlevideo.com': (kind: SplitKind.domain, value: 'googlevideo.com'),
      '.example.org': (kind: SplitKind.domain, value: 'example.org'),
      'госуслуги.рф': (kind: SplitKind.domain, value: 'xn--c1aapkosapc.xn--p1ai'),
      'https://пример.испытание/путь': (kind: SplitKind.domain, value: 'xn--e1afmkfd.xn--80akhbyknj4f'),
      'user@example.com:8080': (kind: SplitKind.domain, value: 'example.com'),
      'localhost': null,
      '8.8.8.8': (kind: SplitKind.ip, value: '8.8.8.8/32'),
      '10.0.0.0/8': (kind: SplitKind.ip, value: '10.0.0.0/8'),
      '2a02:6b8::/32': (kind: SplitKind.ip, value: '2a02:6b8::/32'),
      r'C:\Games\Steam\steam.exe': (kind: SplitKind.app, value: 'steam.exe'),
      '"League of Legends.exe"': (kind: SplitKind.app, value: 'League of Legends.exe'),
      '300.1.1.1': null,
      '10.0.0.0/40': null,
      'просто текст': null,
      '# комментарий': null,
      '': null,
    };
    cases.forEach((input, expected) {
      test('«$input»', () => expect(parseSplitItem(input), expected));
    });
  });

  test('набор правил: виды отдельно, пустой список — пустой набор', () {
    const list = SplitList(apps: ['steam.exe'], domains: ['example.com'], ips: ['10.0.0.0/8']);
    final rules = list.toRuleSet()['rules'] as List;
    expect(rules, hasLength(3));
    expect(rules[1], {
      'domain_suffix': ['example.com'],
    });
    expect(list.toDomainsRuleSet()['rules'], hasLength(1));
    expect(const SplitList().toRuleSet(), {'version': 3, 'rules': <Object>[]});
  });

  test('регулярка программы как в ядре: без учёта регистра, только целое имя', () {
    final source = processPathRegex('League of Legends.exe');
    expect(source.startsWith('(?i)'), isTrue);
    // В Dart нет (?i): проверяем остальное с caseSensitive: false.
    final re = RegExp(source.substring(4), caseSensitive: false);
    expect(re.hasMatch(r'C:\Riot Games\League of Legends\league of legends.exe'), isTrue);
    expect(re.hasMatch(r'C:\Riot Games\NotLeague of Legends.exe'), isFalse);
    expect(re.hasMatch(r'C:\Riot Games\League ofXLegends.exe'), isFalse);
  });

  test('запись переходит из списка в список, а не дублируется', () {
    var s = const SplitTunnel(bypass: SplitList(apps: ['Steam.exe']));
    s = s
        .withList(SplitTarget.bypass, s.bypass.without(SplitKind.app, 'steam.exe'))
        .withList(SplitTarget.via, s.via.withItem(SplitKind.app, 'steam.exe'));
    expect(s.bypass.apps, isEmpty);
    expect(s.via.apps, ['steam.exe']);
    expect(s.targetOf(SplitKind.app, 'STEAM.EXE'), SplitTarget.via);
    expect(SplitTunnel.fromJson(s.toJson()).via.apps, ['steam.exe']);
  });

  test('соединение из Clash API: путь со скобками и припиской пользователя', () {
    final c = NetConnection.fromJson({
      'id': '1',
      'metadata': {
        'processPath': r'C:\Program Files (x86)\Steam\steam.exe (DESKTOP\user)',
        'host': 'store.steampowered.com',
        'destinationIP': '1.2.3.4',
        'destinationPort': '443',
        'network': 'tcp',
      },
      'chains': ['direct §hide§'],
    });
    expect(c.exe, 'steam.exe');
    expect(c.viaVpn, isFalse);
    final vpn = NetConnection.fromJson({
      'metadata': {'processPath': r'C:\Program Files (x86)\Google\chrome.exe'},
      'chains': ['NL', 'select'],
    });
    expect(vpn.exe, 'chrome.exe');
    expect(vpn.viaVpn, isTrue);
  });
}
