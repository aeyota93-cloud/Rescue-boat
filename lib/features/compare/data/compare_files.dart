import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hiddify/features/compare/model/compare_models.dart';
import 'package:loggy/loggy.dart';

/// Папка обмена с ядром (HiddifyOptions.rescue-compare-dir).
String rescueCompareDir(Directory baseDir) => '${baseDir.path}${Platform.pathSeparator}compare';

/// Значение опции ядра: путь к папке, созданной заранее. Передаётся всегда, не зависит от сбора ошибок.
String rescueCompareDirOption(Directory baseDir) {
  final dir = rescueCompareDir(baseDir);
  try {
    Directory(dir).createSync(recursive: true);
  } catch (e, st) {
    Loggy("compare").error("could not create compare dir", e, st);
  }
  return dir;
}

File compareRequestFile(String dir, String id) => File('$dir${Platform.pathSeparator}req-$id.json');

File compareResultFile(String dir, String id) => File('$dir${Platform.pathSeparator}res-$id.json');

/// Новый номер запроса: `[a-z0-9]{12}`.
String newCompareId([Random? random]) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = random ?? Random.secure();
  return List.generate(12, (_) => alphabet[r.nextInt(alphabet.length)]).join();
}

/// Записывает запрос атомарно: во временный файл (ядро его не видит — имя не `req-*.json`), затем переименование.
void writeCompareRequest(String dir, CompareRequest request) {
  Directory(dir).createSync(recursive: true);
  final target = compareRequestFile(dir, request.id);
  final tmp = File('${target.path}.tmp')..writeAsStringSync(jsonEncode(request.toJson()), flush: true);
  tmp.renameSync(target.path);
}

/// Читает ответ ядра; null — файла ещё нет или он не разобрался (ядро пишет атомарно, но
/// чужой номер или мусор пропускаем, следующее чтение через 500 мс).
CompareResult? readCompareResult(String dir, String id) {
  final file = compareResultFile(dir, id);
  try {
    if (!file.existsSync()) return null;
    final result = CompareResult.tryParse(jsonDecode(file.readAsStringSync()));
    return result != null && result.id == id ? result : null;
  } catch (_) {
    return null;
  }
}

/// Убирает req- и res- файлы запроса (и временный, если остался).
void deleteCompareFiles(String dir, String id) {
  for (final f in [
    compareRequestFile(dir, id),
    compareResultFile(dir, id),
    File('${compareRequestFile(dir, id).path}.tmp'),
  ]) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (e, st) {
      Loggy("compare").warning("could not delete ${f.path}", e, st);
    }
  }
}
