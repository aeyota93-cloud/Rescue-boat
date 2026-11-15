import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'audit_support.dart';

void main() {
  testWidgets('REF-6: обновление после ухода карточки не читает активный профиль', (tester) async {
    final h = (await tester.runAsync(AuditHarness.create))!;
    final provider = updateProfileNotifierProvider('p1');
    final sub = h.container.listen(provider, (_, _) {});
    final path = h.paths.file('p1').path;
    final gate = h.core.gates[path] = Completer<void>();
    final entered = h.core.entered.stream.firstWhere((p) => p == path);
    late Future<Object?> update;
    try {
      await tester.runAsync(() async {
        update = outcome(h.container.read(provider.notifier).updateProfile(remote(active: false)));
        await auditWait(entered, 'REF-6');
      });
      sub.close();
      // Минута disposeDelay проходит на виртуальных часах, без реального ожидания.
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      await tester.pump();
      expect(
        h.container.exists(provider),
        isFalse,
        reason: 'REF-6: ожидали уничтоженную карточку после disposeDelay, получили живой provider',
      );
      final reads = h.db.activeReads;
      gate.complete();
      final error = await tester.runAsync(() => auditWait(update, 'REF-6'));
      expect(
        error == null && h.db.activeReads == reads && h.toasts.successes.isEmpty,
        isTrue,
        reason:
            'REF-6: ожидали отсутствие старых ref-действий, получили чтений=${h.db.activeReads - reads}, toast=${h.toasts.successes}, ошибка=$error',
      );
    } finally {
      if (!gate.isCompleted) gate.complete();
      await tester.runAsync(() => auditWait(update, 'REF-6'));
      sub.close();
      await tester.runAsync(h.close);
    }
  }, timeout: auditTimeout);
}
