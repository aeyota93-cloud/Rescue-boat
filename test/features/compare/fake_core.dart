import 'dart:convert';
import 'dart:io';

/// Подставное «ядро» для «Сравнить пути»: смотрит папку обмена и пишет res-файлы так же, как настоящее
/// (сначала во временный файл, потом переименование).
class FakeCore {
  FakeCore(this.dir);

  final Directory dir;

  Directory get compareDir => Directory('${dir.path}${Platform.pathSeparator}compare');

  /// Файлы запросов, которые лежат в папке сейчас.
  List<File> get requests => !compareDir.existsSync()
      ? const []
      : [
          for (final f in compareDir.listSync().whereType<File>())
            if (RegExp(r'req-[a-z0-9]{8,32}\.json$').hasMatch(f.path)) f,
        ];

  List<File> get responses => !compareDir.existsSync()
      ? const []
      : [
          for (final f in compareDir.listSync().whereType<File>())
            if (RegExp(r'res-[a-z0-9]{8,32}\.json$').hasMatch(f.path)) f,
        ];

  List<String> get allFiles => !compareDir.existsSync()
      ? const []
      : ([for (final f in compareDir.listSync().whereType<File>()) f.uri.pathSegments.last]..sort());

  /// Последний запрос приложения как JSON; null — запроса нет.
  Map<String, dynamic>? get request =>
      requests.isEmpty ? null : jsonDecode(requests.last.readAsStringSync()) as Map<String, dynamic>;

  /// Записать ответ (перезаписывается по ходу замеров).
  void respond(
    String id, {
    List<int?> direct = const [],
    List<int?> vpn = const [],
    bool done = false,
    String error = '',
    String target = 'example.com',
    String ip = '93.184.216.34',
    String method = 'tls',
    int? directFirst,
    int? vpnFirst,
    bool vpnEstimate = false,
    bool vpnAvailable = true,
    String vpnNote = '',
  }) {
    compareDir.createSync(recursive: true);
    final body = {
      'v': 1,
      'id': id,
      'target': target,
      'ip': ip,
      'method': method,
      'done': done,
      'started': 1791640000100,
      if (done) 'finished': 1791640012000,
      'error': error,
      if (error.isEmpty)
        'paths': {
          'direct': {'available': true, 'first_ms': directFirst, 'samples': direct, 'note': ''},
          'vpn': {
            'available': vpnAvailable,
            if (vpnEstimate) 'estimate': true,
            'first_ms': vpnFirst,
            'samples': vpn,
            'note': vpnNote,
          },
        },
    };
    final target0 = File('${compareDir.path}${Platform.pathSeparator}res-$id.json');
    final tmp = File('${target0.path}.tmp')..writeAsStringSync(jsonEncode(body), flush: true);
    tmp.renameSync(target0.path);
  }

  /// Записать недописанный (битый) ответ — как будто файл читают посреди записи.
  void respondBroken(String id) {
    compareDir.createSync(recursive: true);
    File('${compareDir.path}${Platform.pathSeparator}res-$id.json').writeAsStringSync('{"v":1,"id":"$id","pa');
  }
}
