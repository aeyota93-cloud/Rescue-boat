import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/servers/widget/servers_page.dart';
import 'audit_support.dart';

void main() {
  testWidgets('A-11: большая сетка строит карточки только возле видимой области', (tester) async {
    final h = (await tester.runAsync(() => AuditHarness.create(group: groupOf(count: 1000))))!;
    try {
      await mountAudit(tester, h, const ServersPage());
      await tester.pump();
      final mounted = find
          .byWidgetPredicate(
            (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('server-card-srv'),
            skipOffstage: false,
          )
          .evaluate()
          .length;
      final last = find.byKey(const ValueKey('server-card-srv999'), skipOffstage: false);
      final lastBuilt = last.evaluate().isNotEmpty;
      expect(
        mounted < 200 && !lastBuilt,
        isTrue,
        reason:
            'A-11: ожидали меньше 200 карточек и отсутствие srv999 до прокрутки, получили $mounted карточек, srv999=$lastBuilt',
      );
      // После исправления последняя карточка должна оставаться достижимой.
      await tester.scrollUntilVisible(last, 2000, maxScrolls: 100, scrollable: find.byType(Scrollable).last);
      expect(last, findsOneWidget, reason: 'A-11: ожидали srv999 после прокрутки, получили отсутствие карточки');
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(h.close);
    }
  }, timeout: auditTimeout);
}
