import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/split_tunnel/model/direct_routes.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/widget/direct_add.dart';

ErrorEvent _e(String ip, ErrorRoute route) => ErrorEvent(
  time: DateTime(2026, 11, 27, 20),
  kind: ErrorKind.timeout,
  app: 'Marvel-Win64-Shipping.exe',
  ip: ip,
  port: 7777,
  network: 'udp',
  route: route,
);

void main() {
  test('errors: only addresses that went directly, without repeats', () {
    final c = candidatesForErrors([
      _e('35.228.147.70', ErrorRoute.direct),
      _e('35.228.147.70', ErrorRoute.direct),
      _e('35.228.147.71', ErrorRoute.direct),
      _e('8.8.8.8', ErrorRoute.vpn),
      _e('2a00::1', ErrorRoute.direct),
    ], const DirectRoutes());
    expect(c.picks.map((p) => p.net.label), ['35.228.147.70', '35.228.147.71']);
    expect(c.picks.first.app, 'Marvel-Win64-Shipping.exe');
    expect(c.viaVpn, 1);
  });

  test('menu state says why nothing can be added', () {
    expect(directMenuState(null, online: true).enabled, isFalse);
    expect(directMenuState(const DirectCandidates(), online: false).hint, contains('не в сети'));
    expect(directMenuState(const DirectCandidates(viaVpn: 2), online: true).hint, contains('«Мимо VPN»'));
    expect(directMenuState(const DirectCandidates(already: 1), online: true).title, 'Мимо Шлюпки ✓');
    final one = DirectCandidates(picks: [(net: V4Net.tryParse('1.1.1.1')!, app: '', site: '')]);
    expect(directMenuState(one, online: true).title, 'Мимо Шлюпки: 1 адрес');
    expect(directMenuState(one, online: true).enabled, isTrue);
    expect(addressesRu(5), '5 адресов');
    expect(directSkippedText(const DirectCandidates(viaVpn: 1, shared: 2)), contains('через VPN'));
  });

  test('what is added, for the dialog', () {
    expect(directWhatOf((kind: SplitKind.app, value: 'Overwatch.exe'), 'Overwatch'), 'программы Overwatch');
    expect(directWhatOf((kind: SplitKind.domain, value: 'discord.gg'), 'discord.gg'), 'сайта discord.gg');
    expect(directWhatOf((kind: SplitKind.ip, value: '1.2.3.4/32'), '1.2.3.4'), 'IP 1.2.3.4');
  });
}
