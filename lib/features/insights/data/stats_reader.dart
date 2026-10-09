import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:hiddify/features/insights/model/insights_models.dart';

/// Папка статистики ядра (HiddifyOptions.rescue-stats-dir).
String rescueStatsDir(Directory baseDir) => '${baseDir.path}${Platform.pathSeparator}stats';

/// Имя файла за местные сутки: errors-20251009.jsonl.
String statsFileName(String prefix, DateTime day) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '$prefix-${day.year}${two(day.month)}${two(day.day)}.jsonl';
}

/// Местные даты (полночь) от from до to включительно.
List<DateTime> statsDays(DateTime from, DateTime to) {
  final days = <DateTime>[];
  var d = DateTime(from.year, from.month, from.day);
  final last = DateTime(to.year, to.month, to.day);
  while (!d.isAfter(last)) {
    days.add(d);
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return days;
}

/// Разбор JSON Lines: строки, которые не парсятся (недописанная последняя, мусор), пропускаются,
/// неизвестные поля игнорируются.
List<T> parseJsonLines<T>(Uint8List bytes, T? Function(Map<String, dynamic>) parse) {
  final out = <T>[];
  for (final line in const LineSplitter().convert(utf8.decode(bytes, allowMalformed: true))) {
    if (line.trim().isEmpty) continue;
    try {
      final json = jsonDecode(line);
      if (json is! Map<String, dynamic>) continue;
      final record = parse(json);
      if (record != null) out.add(record);
    } catch (_) {
      // битая строка — пропускаем
    }
  }
  return out;
}

/// Читает errors-*.jsonl и quality-*.jsonl из папки статистики.
///
/// Файлы только дописываются, поэтому для каждого помним, до какого места он разобран:
/// при следующем чтении разбираются только новые строки. Хвост без перевода строки (ядро
/// ещё пишет) разбирается каждый раз заново и в кэш не попадает. Файл стал короче —
/// разбираем с начала.
class StatsReader {
  StatsReader(this.dir);

  final String dir;

  final _errors = <String, _FileCache<ErrorEvent>>{};
  final _quality = <String, _FileCache<QualityRecord>>{};
  Future<void> _queue = Future.value();

  // Большие куски (первое чтение месяца замеров) разбираем в отдельном изоляте, чтобы не
  // подвешивать интерфейс.
  static const _isolateThreshold = 256 * 1024;

  /// Ошибки с from по to (без сортировки).
  Future<List<ErrorEvent>> errors(DateTime from, DateTime to) =>
      _read('errors', from, to, _errors, ErrorEvent.tryParse, (e) => e.time);

  /// Замеры и счётчики с from по to (без сортировки).
  Future<List<QualityRecord>> quality(DateTime from, DateTime to) =>
      _read('quality', from, to, _quality, QualityRecord.tryParse, (r) => r.time);

  // Чтения по очереди: два провайдера не должны дописывать один кэш одновременно.
  Future<List<T>> _read<T>(
    String prefix,
    DateTime from,
    DateTime to,
    Map<String, _FileCache<T>> cache,
    T? Function(Map<String, dynamic>) parse,
    DateTime Function(T) timeOf,
  ) {
    final result = _queue.then((_) async {
      final out = <T>[];
      final days = statsDays(from, to);
      for (final day in days) {
        final path = '$dir${Platform.pathSeparator}${statsFileName(prefix, day)}';
        for (final r in await _file(path, day, cache, parse)) {
          final t = timeOf(r);
          if (!t.isBefore(from) && !t.isAfter(to)) out.add(r);
        }
      }
      // Старше месяца нам не нужно ни для одного экрана.
      final oldest = DateTime(to.year, to.month, to.day - 32);
      cache.removeWhere((_, c) => c.day.isBefore(oldest));
      return out;
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<T>> _file<T>(
    String path,
    DateTime day,
    Map<String, _FileCache<T>> cache,
    T? Function(Map<String, dynamic>) parse,
  ) async {
    final file = File(path);
    final int size;
    try {
      size = await file.length();
    } on FileSystemException {
      cache.remove(path);
      return const [];
    }
    var c = cache[path];
    if (c == null || size < c.offset) {
      c = _FileCache<T>(day);
      cache[path] = c;
    }
    if (size == c.offset) return c.records;

    final Uint8List bytes;
    try {
      final raf = await file.open();
      try {
        await raf.setPosition(c.offset);
        bytes = await raf.read(size - c.offset);
      } finally {
        await raf.close();
      }
    } on FileSystemException {
      return c.records;
    }

    final end = bytes.lastIndexOf(0x0A) + 1;
    if (end > 0) {
      final complete = Uint8List.sublistView(bytes, 0, end);
      c.records.addAll(
        complete.length > _isolateThreshold ? await _parseInIsolate(complete, parse) : parseJsonLines(complete, parse),
      );
      c.offset += end;
    }
    if (end == bytes.length) return c.records;
    final tail = parseJsonLines(Uint8List.sublistView(bytes, end), parse);
    return tail.isEmpty ? c.records : [...c.records, ...tail];
  }
}

// Отдельная функция, чтобы в изолят ушли только байты и разборщик.
Future<List<T>> _parseInIsolate<T>(Uint8List bytes, T? Function(Map<String, dynamic>) parse) =>
    Isolate.run(() => parseJsonLines(bytes, parse));

class _FileCache<T> {
  _FileCache(this.day);

  final DateTime day;
  int offset = 0;
  final records = <T>[];
}
