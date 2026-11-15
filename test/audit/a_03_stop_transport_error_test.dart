import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'audit_grpc.dart';
import 'audit_support.dart';

void main() {
  for (final error in [
    const GrpcError.unavailable('audit: канал недоступен'),
    const GrpcError.deadlineExceeded('audit: срок истёк'),
  ]) {
    test('A-03: Stop возвращает ошибку транспорта ${error.codeName} без ложного stopped', () async {
      final channel = MemoryChannel((path, call) => call.error(error));
      final container = ProviderContainer();
      final service = container.read(Provider(HiddifyCoreService.new));
      service.core.bgClient = CoreClient(channel);
      service.currentState = const CoreStatus.started();
      final states = <CoreStatus>[];
      final sub = service.statusController.listen(states.add);
      try {
        final result = await auditWait(service.stop().run(), 'A-03');
        await flushAudit();
        expect(
          result.isLeft() && !states.contains(const CoreStatus.stopped()),
          isTrue,
          reason: 'A-03: ожидали Left без доказанного stopped, получили $result и состояния $states',
        );
      } finally {
        await sub.cancel();
        await channel.terminate();
        await service.statusController.close();
        container.dispose();
      }
    }, timeout: auditTimeout);
  }
}
