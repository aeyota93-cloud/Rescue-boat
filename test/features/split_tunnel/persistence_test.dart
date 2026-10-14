import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';

import '../screens_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('rescue_persistence_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('повреждение состояния восстанавливается из последней рабочей копии', () async {
    var c = await screensContainer(dir);
    final notifier = c.read(splitTunnelProvider.notifier);
    notifier.add(SplitTarget.via, SplitKind.domain, 'example.org');
    notifier.add(SplitTarget.via, SplitKind.domain, 'second.example.org');
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    File('${dir.path}/split-tunnel.json').writeAsStringSync('{broken');
    c = await screensContainer(dir);
    expect(c.read(splitTunnelProvider).via.domains, ['example.org']);
    expect(jsonDecode(File('${dir.path}/split-tunnel.json').readAsStringSync()), isA<Map>());
    await Future<void>.delayed(Duration.zero);
    expect(c.read(splitTunnelIssueProvider), contains('резервной копии'));
    c.dispose();
  });

  test('без резервной копии повреждение не затирает рабочие файлы VPN', () async {
    File('${dir.path}/split-tunnel.json').writeAsStringSync('{broken');
    Directory('${dir.path}/split').createSync();
    final rules = File('${dir.path}/split/via-vpn.json')..writeAsStringSync('last working export');
    final c = await screensContainer(dir);
    c.read(splitTunnelProvider);
    c.read(splitTunnelProvider.notifier).add(SplitTarget.via, SplitKind.domain, 'example.org');
    expect(rules.readAsStringSync(), 'last working export');
    expect(File('${dir.path}/split-tunnel.json').readAsStringSync(), '{broken');
    await Future<void>.delayed(Duration.zero);
    expect(c.read(splitTunnelIssueProvider), contains('повреждённый'));
    c.dispose();
  });

  test('ошибка записи отменяет UI-изменение и восстанавливает экспорт', () async {
    final c = await screensContainer(dir);
    c.read(splitTunnelProvider);
    final rules = File('${dir.path}/split/via-vpn.json');
    final before = rules.readAsStringSync();
    File('${dir.path}/split-tunnel.json').deleteSync();
    Directory('${dir.path}/split-tunnel.json').createSync();
    final added = c
        .read(splitTunnelProvider.notifier)
        .addItems([(kind: SplitKind.domain, value: 'example.org')], (target: SplitTarget.via, server: null));
    expect(added, isFalse);
    expect(c.read(splitTunnelProvider).via.domains, isNot(contains('example.org')));
    expect(rules.readAsStringSync(), before);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(splitTunnelIssueProvider), contains('отменено'));
    expect(Directory(dir.path).listSync().where((file) => file.path.endsWith('.tmp')), isEmpty);
    c.dispose();
  });

  test('ошибка одного набора правил не меняет сохранённое состояние', () async {
    final c = await screensContainer(dir);
    c.read(splitTunnelProvider);
    final stateFile = File('${dir.path}/split-tunnel.json');
    final before = stateFile.readAsStringSync();
    File('${dir.path}/split/bypass-vpn.json').deleteSync();
    Directory('${dir.path}/split/bypass-vpn.json').createSync();
    c.read(splitTunnelProvider.notifier).add(SplitTarget.via, SplitKind.domain, 'example.org');
    expect(stateFile.readAsStringSync(), before);
    expect(c.read(splitTunnelProvider).via.domains, isNot(contains('example.org')));
    expect(File('${dir.path}/split/via-vpn.json').readAsStringSync(), isNot(contains('example.org')));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(splitTunnelIssueProvider), isNotNull);
    c.dispose();
  });
}
