import 'dart:async';
import 'package:grpc/grpc.dart';
import 'package:grpc/src/client/channel.dart' as channel;

/// Канал в памяти. Дедлайн исполняется только при переданном CallOptions.timeout.
class MemoryChannel implements channel.ClientChannel {
  MemoryChannel(this.respond);
  final void Function(String, MemoryCall<dynamic, dynamic>) respond;
  final calls = <MemoryCall<dynamic, dynamic>>[];
  @override
  ClientCall<Q, R> createCall<Q, R>(ClientMethod<Q, R> method, Stream<Q> requests, CallOptions options) {
    final call = MemoryCall<Q, R>(options);
    calls.add(call);
    scheduleMicrotask(() => respond(method.path, call));
    return call;
  }

  @override
  Stream<ConnectionState> get onConnectionStateChanged => const Stream.empty();
  @override
  Future<void> shutdown() => terminate();
  @override
  Future<void> terminate() async {
    for (final call in calls) {
      await call.cancel();
    }
  }
}

class MemoryCall<Q, R> implements ClientCall<Q, R> {
  MemoryCall(this.options) {
    if (options.timeout case final timeout?) {
      timer = Timer(timeout, () => error(const GrpcError.deadlineExceeded('audit: срок RPC истёк')));
    }
  }
  @override
  final CallOptions options;
  final controller = StreamController<R>();
  Timer? timer;
  @override
  Stream<R> get response => controller.stream;
  void add(R value) {
    if (!controller.isClosed) controller.add(value);
  }

  void error(Object error) {
    if (!controller.isClosed) {
      controller.addError(error);
      finish();
    }
  }

  void finish() {
    timer?.cancel();
    if (!controller.isClosed) unawaited(controller.close());
  }

  @override
  Future<void> cancel() async {
    timer?.cancel();
    if (!controller.isClosed) unawaited(controller.close());
  }

  @override
  Future<Map<String, String>> get headers async => {};
  @override
  Future<Map<String, String>> get trailers async => {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
