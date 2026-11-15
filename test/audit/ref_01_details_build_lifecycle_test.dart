import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/features/profile/details/profile_details_notifier.dart';
import 'audit_support.dart';

void main() {
  test('REF-1: закрытый редактор не начинает чтение конфига после ответа БД', () async {
    final h = await AuditHarness.create();
    addTearDown(h.close);
    h.db.getGate = Completer<ProfileEntry?>();
    final provider = profileDetailsNotifierProvider('p1');
    final sub = h.container.listen(provider, (_, _) {});
    await auditWait(h.db.getEntered.future, 'REF-1');
    sub.close();
    await auditWait(h.container.pump(), 'REF-1');
    await auditWait(h.container.pump(), 'REF-1');
    expect(
      h.container.exists(provider),
      isFalse,
      reason: 'REF-1: ожидали уничтоженный редактор до ответа БД, получили живой provider',
    );
    h.db.getGate!.complete(h.db.entries['p1']);
    await flushAudit();
    expect(
      h.core.configReads,
      0,
      reason: 'REF-1: ожидали отмену чтения после закрытия редактора, получили ${h.core.configReads} вызовов ядра',
    );
  }, timeout: auditTimeout);
}
