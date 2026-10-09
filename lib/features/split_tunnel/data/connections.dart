import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Шлюпка: пароль Clash API ядра на время работы программы. Его же получает ядро
/// (HiddifyOptions.web-secret), иначе оно придумало бы свой, и список соединений был бы недоступен.
final clashApiSecret = _randomSecret();

String _randomSecret() {
  final r = Random.secure();
  return List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join();
}

/// Одно соединение из ядра.
class NetConnection {
  const NetConnection({
    required this.id,
    required this.exe,
    required this.host,
    required this.ip,
    required this.port,
    required this.network,
    required this.viaVpn,
    required this.upload,
    required this.download,
  });

  final String id;

  /// Имя программы («chrome.exe»), пусто, если ядро её не определило.
  final String exe;

  /// Сайт, если ядро его узнало (из DNS или из TLS), иначе пусто.
  final String host;
  final String ip;
  final String port;
  final String network;
  final bool viaVpn;
  final int upload;
  final int download;

  factory NetConnection.fromJson(Map<String, dynamic> json) {
    final meta = json['metadata'] as Map<String, dynamic>? ?? const {};
    // processPath бывает с припиской « (пользователь)».
    final path = (meta['processPath'] as String? ?? '').replaceFirst(RegExp(r' \([^()\/]*\)$'), '');
    final exe = path.isEmpty ? '' : path.split(RegExp(r'[\\/]')).last;
    final chains = (json['chains'] as List<dynamic>? ?? const []).cast<String>();
    final direct = chains.isNotEmpty && chains.first.startsWith('direct');
    final block = chains.isNotEmpty && chains.first.startsWith('block');
    return NetConnection(
      id: json['id'] as String? ?? '',
      exe: exe,
      host: meta['host'] as String? ?? '',
      ip: meta['destinationIP'] as String? ?? '',
      port: meta['destinationPort'] as String? ?? '',
      network: meta['network'] as String? ?? '',
      viaVpn: !direct && !block,
      upload: (json['upload'] as num? ?? 0).toInt(),
      download: (json['download'] as num? ?? 0).toInt(),
    );
  }
}

/// Текущие соединения через Clash API ядра (127.0.0.1, только с паролем).
/// null — ядро не запущено или API недоступен.
Future<List<NetConnection>?> fetchConnections(int port) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/connections'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $clashApiSecret');
    final response = await request.close().timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final list = (json['connections'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    return list.map(NetConnection.fromJson).toList();
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
