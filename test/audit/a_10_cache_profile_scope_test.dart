import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/servers/model/rescue_servers.dart';
import 'package:hiddify/features/servers/notifier/failover.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hiddify/features/split_tunnel/widget/place_menu.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'audit_support.dart';

void main() {
  testWidgets('A-10: профиль B не предлагает серверы из сохранённого списка A', (tester) async {
    final cached = rescueServersOf(groupOf(prefix: 'only-A'))!.encode();
    // Состояние после A → B при выключенном VPN, без списка серверов B от ядра.
    final h = (await tester.runAsync(
      () => AuditHarness.create(
        profiles: [remote(id: 'B', url: 'https://subscription.test/B')],
        prefs: {lastServersKey: cached},
      ),
    ))!;
    h.core.groups.add(null);
    h.core.statuses.add(const CoreStatus.stopped());
    try {
      await mountAudit(
        tester,
        h,
        Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final split = ref.watch(splitTunnelProvider);
              final servers = ref.watch(rescueServersProvider);
              return Column(
                children: placeMenuItems(
                  ref: ref,
                  split: split,
                  servers: servers,
                  items: const [(kind: SplitKind.domain, value: 'example.test')],
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      final stale = find.byKey(const ValueKey('place-server-only-A0'));
      final count = stale.evaluate().length;
      expect(
        count,
        0,
        reason: 'A-10: ожидали отсутствие серверов A в меню B, получили $count доступных пунктов only-A0',
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(h.close);
    }
  }, timeout: auditTimeout);
}
