import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/compare/model/compare_target.dart';
import 'package:hiddify/features/compare/notifier/compare_notifier.dart';
import 'package:hiddify/features/compare/widget/compare_paths_dialog.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/overview/notifier/vpn_status.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../features/compare/fake_core.dart';
import 'audit_support.dart';

void main() {
  testWidgets('A-09: Connected без пинга позволяет сравнить другой адрес', (tester) async {
    final h = (await tester.runAsync(() => AuditHarness.create(group: groupOf(delay: 65000))))!;
    try {
      await mountAudit(
        tester,
        h,
        const Scaffold(
          body: ComparePathsDialog(subject: CompareSubject(endpoints: [CompareEndpoint('www.example.test')])),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        h.container.read(connectionNotifierProvider).valueOrNull,
        isA<Connected>(),
        reason: 'A-09: ожидали настоящий Connected из статуса ядра, получили другое состояние',
      );
      final vpn = h.container.read(vpnStatusProvider);
      final files = FakeCore(h.dir).requests;
      final phase = h.container.read(compareProvider).phase;
      expect(
        files.isNotEmpty && phase != ComparePhase.idle,
        isTrue,
        reason:
            'A-09: ожидали req-файл и запуск диагностики при Connected, получили файлов=${files.length}, phase=$phase, on=${vpn.on}',
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(h.close);
    }
  }, timeout: auditTimeout);
}
