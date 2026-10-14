import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/split_tunnel/notifier/live_connections_notifier.dart';

import '../screens_test_helpers.dart';

class RealAuditHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'параллельные соединения сохраняют оба ID и весь трафик',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final dir = Directory.systemTemp.createTempSync('rb_audit_');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'connections': [
              for (var i = 1; i <= 2; i++)
                {
                  'id': 'session-$i',
                  'upload': 0,
                  'download': i * 11,
                  'chains': ['server'],
                  'metadata': {
                    'processPath': 'C:/Fake/app.exe',
                    'host': 'example.org',
                    'destinationIP': '203.0.113.$i',
                    'destinationPort': '443',
                    'network': 'tcp',
                  },
                },
            ],
          }),
        );
        request.response.close();
      });
      final c = await screensContainer(dir, prefs: {'clash-api-port': server.port});
      final sub = c.listen(liveConnectionsProvider, (_, _) {});
      final result = await c.read(liveConnectionsProvider.future).timeout(const Duration(seconds: 3));
      expect(result, hasLength(2));
      expect(result!.map((connection) => connection.id), ['session-1', 'session-2']);
      expect(result.fold<int>(0, (sum, connection) => sum + connection.download), 33);
      sub.close();
      c.dispose();
      await serving.cancel();
      await server.close(force: true);
      dir.deleteSync(recursive: true);
    }, RealAuditHttp()),
  );
}
