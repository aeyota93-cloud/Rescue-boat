import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/details/profile_details_notifier.dart';
import 'audit_support.dart';

void main() {
  test('REF-3: завершение сохранения закрытого редактора не показывает toast', () async {
    final h = await AuditHarness.create();
    addTearDown(h.close);
    final provider = profileDetailsNotifierProvider('p1');
    final sub = h.container.listen(provider, (_, _) {});
    await auditWait(h.container.read(provider.future), 'REF-3');
    final path = h.paths.file('p1').path;
    final gate = h.core.gates[path] = Completer<void>();
    final entered = h.core.entered.stream.firstWhere((p) => p == path);
    final save = outcome(h.container.read(provider.notifier).save());
    await auditWait(entered, 'REF-3');
    sub.close();
    await auditWait(h.container.pump(), 'REF-3');
    await auditWait(h.container.pump(), 'REF-3');
    expect(
      h.container.exists(provider),
      isFalse,
      reason: 'REF-3: ожидали закрытый редактор до ответа валидации, получили живой provider',
    );
    gate.complete();
    final error = await auditWait(save, 'REF-3');
    expect(
      error == null && h.toasts.successes.isEmpty,
      isTrue,
      reason:
          'REF-3: ожидали завершение без старого toast и исключения, получили toast=${h.toasts.successes}, ошибка=$error',
    );
  }, timeout: auditTimeout);
}
