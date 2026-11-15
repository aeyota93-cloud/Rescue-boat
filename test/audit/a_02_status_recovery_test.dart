import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'audit_grpc.dart';
import 'audit_support.dart';

void main() {
  test('A-02: после ошибки статуса публикуется потеря связи и восстанавливается подписка', () async {
    var listeners = 0;
    late MemoryCall<dynamic, dynamic> first;
    final second = Completer<MemoryCall<dynamic, dynamic>>();
    final lost = Completer<void>();
    final recovered = Completer<void>();
    final channel = MemoryChannel((path, call) {
      listeners++;
      if (listeners == 1) {
        first = call;
        call.add(CoreInfoResponse(coreState: CoreStates.STARTED));
      } else if (!second.isCompleted) {
        second.complete(call);
      }
    });
    final container = ProviderContainer();
    final service = container.read(Provider(HiddifyCoreService.new));
    service.core.bgClient = CoreClient(channel);
    final states = <CoreStatus>[];
    final sub = service.watchStatus().listen(
      (s) {
        states.add(s);
        if (listeners == 1 && s != const CoreStatus.started() && !lost.isCompleted) lost.complete();
        if (listeners > 1 && s == const CoreStatus.stopped() && !recovered.isCompleted) recovered.complete();
      },
      onError: (Object error) {
        if (!lost.isCompleted) lost.complete();
      },
    );
    try {
      await auditWait(service.statusController.firstWhere((s) => s == const CoreStatus.started()), 'A-02');
      first.error(const GrpcError.unavailable('audit: разрыв канала'));
      await auditWait(Future.wait([lost.future, second.future]), 'A-02: потеря связи и повторная подписка', seconds: 3);
      (await second.future).add(CoreInfoResponse(coreState: CoreStates.STOPPED));
      await auditWait(recovered.future, 'A-02', seconds: 3);
      expect(
        states.any((s) => s != const CoreStatus.started()) && listeners >= 2,
        isTrue,
        reason: 'A-02: ожидали уведомление о потере связи и повторную подписку, получили $listeners listener и $states',
      );
    } finally {
      await sub.cancel();
      await service.stopListenSingle('');
      await channel.terminate();
      await service.statusController.close();
      container.dispose();
    }
  }, timeout: auditTimeout);
}
