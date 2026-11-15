import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/split_tunnel/data/connections.dart';
import 'package:hiddify/features/split_tunnel/notifier/live_connections_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'audit_support.dart';

class _Headers implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.body);
  final Stream<List<int>> body;
  @override
  int get statusCode => 200;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => body.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final _Response response;
  @override
  final headers = _Headers();
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.owner);
  final _Http owner;
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    owner.requests++;
    return _Request(
      _Response(
        owner.requests == 1
            ? owner.unfinished.stream
            : Stream.value(utf8.encode('{"connections":[{"id":"second","metadata":{"host":"example.test"}}]}')),
      ),
    );
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Http extends HttpOverrides {
  final unfinished = StreamController<List<int>>();
  final clients = <_Client>[];
  int requests = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = _Client(this);
    clients.add(client);
    return client;
  }
}

void main() {
  for (final dispose in [false, true]) {
    testWidgets(
      dispose
          ? 'A-08: уход со страницы закрывает клиент с незавершённым телом'
          : 'A-08: незавершённое тело истекает по сроку и следующий опрос получает снимок',
      (tester) async {
        final h = (await tester.runAsync(AuditHarness.create))!;
        final http = _Http();
        final previous = HttpOverrides.current;
        HttpOverrides.global = http;
        final snapshots = <String>[];
        final sub = h.container.listen(liveConnectionsProvider, (_, next) {
          for (final c in next.valueOrNull ?? const <NetConnection>[]) {
            snapshots.add(c.id);
          }
        });
        try {
          await tester.pump();
          http.unfinished.add(utf8.encode('{"connections":['));
          await tester.pump();
          expect(http.requests, 1, reason: 'A-08: ожидали первый запрос в памяти, получили ${http.requests}');
          if (dispose) {
            sub.close();
            await tester.pump();
            await tester.pump();
            expect(
              http.clients.first.closed,
              isTrue,
              reason: 'A-08: ожидали закрытый HTTP-клиент после dispose, получили открытый клиент',
            );
          } else {
            // Виртуальные часы: срок тела 3 с, следующий тик на 4-й секунде.
            await tester.pump(const Duration(seconds: 3));
            await tester.pump(const Duration(seconds: 1));
            await tester.pump();
            expect(
              http.requests >= 2 && snapshots.contains('second'),
              isTrue,
              reason:
                  'A-08: ожидали второй запрос и снимок за 4 с, получили запросов=${http.requests}, снимки=$snapshots',
            );
          }
        } finally {
          sub.close();
          h.container.invalidate(liveConnectionsProvider);
          await tester.pump();
          await http.unfinished.close();
          await tester.pump();
          HttpOverrides.global = previous;
          await tester.runAsync(h.close);
        }
      },
      timeout: auditTimeout,
    );
  }
}
