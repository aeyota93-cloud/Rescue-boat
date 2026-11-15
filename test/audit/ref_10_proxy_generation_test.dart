import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'audit_support.dart';

void main() {
  test('REF-10: старый select не перезаписывает группу после restart', () async {
    final h = await AuditHarness.create(group: groupOf(prefix: 'old'));
    addTearDown(h.close);
    final provider = proxiesOverviewNotifierProvider;
    final sub = h.container.listen(provider, (_, _) {});
    try {
      await auditWait(h.container.read(provider.future), 'REF-10');
      h.core.selectGate = Completer<void>();
      final select = outcome(h.container.read(provider.notifier).changeProxy('select', 'old1'));
      await auditWait(h.core.selectEntered.future, 'REF-10');
      h.core.groups.add(groupOf(prefix: 'new'));
      h.container.read(coreRestartSignalProvider.notifier).restart();
      await auditWait(h.container.pump(), 'REF-10');
      final fresh = await auditWait(h.container.read(provider.future), 'REF-10');
      expect(
        fresh?.selected,
        'new0',
        reason: 'REF-10: ожидали новую группу после restart, получили ${fresh?.selected}',
      );
      h.core.selectGate!.complete();
      final error = await auditWait(select, 'REF-10');
      final selected = h.container.read(provider).valueOrNull?.selected;
      expect(
        error == null && selected == 'new0',
        isTrue,
        reason: 'REF-10: ожидали сохранение новой группы new0, получили $selected, ошибка=$error',
      );
    } finally {
      sub.close();
    }
  }, timeout: auditTimeout);
}
