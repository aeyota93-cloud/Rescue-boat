import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'audit_grpc.dart';
import 'audit_support.dart';

void main() {
  test('A-01: молчащий Stop освобождает очередь с ошибкой по сроку RPC', () async {
    final accepted = Completer<void>();
    final channel = MemoryChannel((path, call) {
      accepted.complete();
    });
    final provider = Provider(HiddifyCoreService.new);
    final container = ProviderContainer();
    final service = container.read(provider);
    service.core.bgClient = CoreClient(channel);
    final queue = ConnectionOperationQueue();
    final stop = queue.run(() => service.stop().run());
    // Сразу подписываемся и на ошибку, чтобы поздняя очистка не дала unhandled error.
    final stopped = outcome(stop);
    var reconciled = false;
    final reconcile = queue.run(() async {
      reconciled = true;
    });
    try {
      await auditWait(accepted.future, 'A-01');
      await auditWait(reconcile, 'A-01', seconds: 3);
      final error = await auditWait(stopped, 'A-01');
      expect(
        error == null && (await stop).isLeft() && reconciled,
        isTrue,
        reason: 'A-01: ожидали ошибку Stop и выполнение сверки, получили успех или заблокированную очередь',
      );
    } finally {
      await channel.terminate();
      await auditWait(stopped, 'A-01: очистка');
      await auditWait(outcome(reconcile), 'A-01: очистка');
      await service.statusController.close();
      container.dispose();
    }
  }, timeout: auditTimeout);
}
