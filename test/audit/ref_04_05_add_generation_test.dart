import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'audit_support.dart';

void main() {
  for (final manual in [false, true]) {
    final id = manual ? 'REF-5' : 'REF-4';
    test('$id: отменённое добавление не завершает и не заменяет новое', () async {
      const newUrl = 'https://subscription.test/new';
      final h = await AuditHarness.create(
        profiles: [
          remote(),
          remote(id: 'p2', url: newUrl, active: false),
        ],
      );
      addTearDown(h.close);
      h.http.bodies[newUrl] = validUri;
      final oldPath = h.paths.file('p1').path;
      final newPath = h.paths.file('p2').path;
      final oldGate = h.core.gates[oldPath] = Completer<void>();
      final newGate = h.core.gates[newPath] = Completer<void>();
      final oldEntered = h.core.entered.stream.firstWhere((p) => p == oldPath);
      final sub = h.container.listen(addProfileNotifierProvider, (_, _) {});
      Future<void> add(String url) {
        final notifier = h.container.read(addProfileNotifierProvider.notifier);
        return manual
            ? notifier.addManual(
                url: url,
                userOverride: const UserOverride(name: 'Новый'),
              )
            : notifier.addClipboard(url);
      }

      final oldResult = outcome(add(profileUrl));
      Future<Object?>? newResult;
      try {
        await auditWait(oldEntered, id);
        // Так же отменяет LoadingAddProfile: invalidate, затем следующий build.
        h.container.invalidate(addProfileNotifierProvider);
        h.container.read(addProfileNotifierProvider);
        final newEntered = h.core.entered.stream.firstWhere((p) => p == newPath);
        newResult = outcome(add(newUrl));
        await auditWait(newEntered, id);
        oldGate.complete();
        final error = await auditWait(oldResult, id);
        final state = h.container.read(addProfileNotifierProvider);
        expect(
          error == null && state.isLoading && h.toasts.successes.isEmpty,
          isTrue,
          reason:
              '$id: ожидали загрузку нового запроса без старого toast, получили $state, toast=${h.toasts.successes}, ошибка=$error',
        );
      } finally {
        if (!oldGate.isCompleted) oldGate.complete();
        if (!newGate.isCompleted) newGate.complete();
        await auditWait(oldResult, id);
        if (newResult != null) await auditWait(newResult, id);
        sub.close();
      }
    }, timeout: auditTimeout);
  }
}
