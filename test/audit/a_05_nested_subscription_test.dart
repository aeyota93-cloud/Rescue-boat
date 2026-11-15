import 'package:flutter_test/flutter_test.dart';
import 'audit_support.dart';

void main() {
  test('A-05: ошибка вложенной подписки сохраняет прежний полный профиль', () async {
    final h = await AuditHarness.create();
    addTearDown(h.close);
    const nested = 'https://subscription.test/nested';
    h.http.bodies[profileUrl] = '$validUri\n$nested';
    h.http.failures.add(nested);
    final oldEntry = h.db.entries['p1'];
    final file = h.paths.file('p1')..writeAsStringSync('прежний полный конфиг');
    final result = await auditWait(h.repo.upsertRemote(profileUrl).run(), 'A-05');
    expect(
      h.http.requests,
      contains(nested),
      reason: 'A-05: ожидали запрос вложенной части, получили ${h.http.requests}',
    );
    expect(
      result.isLeft() &&
          h.db.edits == 0 &&
          h.db.entries['p1'] == oldEntry &&
          file.readAsStringSync() == 'прежний полный конфиг',
      isTrue,
      reason:
          'A-05: ожидали Left без commit, получили $result, edit=${h.db.edits}, конфиг=${file.readAsStringSync().replaceAll(RegExp(r"\s+"), " ")}',
    );
  }, timeout: auditTimeout);
}
