import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'audit_support.dart';

void main() {
  for (final mode in ['remote', 'offline', 'rejected']) {
    test('A-06: $mode удаляет основной и вложенные временные файлы после выполнения', () async {
      final h = await AuditHarness.create();
      addTearDown(h.close);
      h.http.bodies[profileUrl] = '$validUri\nhttps://subscription.test/nested';
      h.http.bodies['https://subscription.test/nested'] = validUri;
      h.core.rejectValidation = mode == 'rejected';
      final result = await auditWait(
        (mode == 'offline' ? h.repo.offlineUpdate(remote(), validUri) : h.repo.upsertRemote(profileUrl)).run(),
        'A-06',
      );
      expect(result.isLeft(), mode == 'rejected', reason: 'A-06: ожидали штатный исход $mode, получили $result');
      if (mode != 'rejected') {
        expect(
          h.paths.file('p1').readAsStringSync(),
          contains(validUri),
          reason: 'A-06: ожидали сохранённый рабочий конфиг, получили пустой или другой файл',
        );
      }
      final leftovers = h.paths.directory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.tmp.json'))
          .map((f) => f.path)
          .toList();
      expect(leftovers, isEmpty, reason: 'A-06: ожидали очистку tmp после $mode, получили $leftovers');
    }, timeout: auditTimeout);
  }
}
