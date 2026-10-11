/// Шлюпка: «Сравнить пути» — модели обмена с ядром и вычисление вывода.
/// Договор: docs/redesign/compare-paths.md. Без виджетов и файлов, чтобы проверять тестами.
library;

import 'dart:math' as math;

/// Одна дорога из ответа ядра (`paths.direct` / `paths.vpn`).
class PathResult {
  const PathResult({
    this.available = true,
    this.estimate = false,
    this.firstMs,
    this.samples = const [],
    this.note = '',
  });

  /// false — дорогу измерить нельзя (см. [note]).
  final bool available;

  /// true — вместо замера цели дана оценка качества туннеля (игры по UDP).
  final bool estimate;

  /// Первое подключение: от начала соединения до конца TLS-рукопожатия, мс.
  final int? firstMs;

  /// Задержки в мс, null — неудача (таймаут).
  final List<int?> samples;
  final String note;

  PathStats get stats => PathStats.of(samples);

  factory PathResult.fromJson(Map<String, dynamic> json) {
    int? ms(Object? v) => v is num ? v.round() : null;
    final raw = json['samples'];
    return PathResult(
      available: json['available'] as bool? ?? true,
      estimate: json['estimate'] as bool? ?? false,
      firstMs: ms(json['first_ms']),
      samples: raw is List ? [for (final v in raw) ms(v)] : const [],
      note: json['note'] as String? ?? '',
    );
  }
}

/// Ответ ядра `res-<id>.json`. Перезаписывается по ходу замеров ([done] = false), последний раз — [done] = true.
class CompareResult {
  const CompareResult({
    required this.id,
    this.target = '',
    this.ip = '',
    this.method = '',
    this.done = false,
    this.error = '',
    this.direct,
    this.vpn,
  });

  final String id;
  final String target;

  /// Адрес, полученный прямым DNS (для показа).
  final String ip;

  /// `tls` или `icmp`.
  final String method;
  final bool done;

  /// Непустой — запрос не выполнить целиком.
  final String error;
  final PathResult? direct;
  final PathResult? vpn;

  /// Сколько замеров по обеим дорогам уже пришло.
  int get samplesDone => (direct?.samples.length ?? 0) + (vpn?.samples.length ?? 0);

  /// null — не разобралось (не тот JSON, нет id).
  static CompareResult? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final paths = json['paths'];
    PathResult? path(String key) {
      final p = paths is Map<String, dynamic> ? paths[key] : null;
      return p is Map<String, dynamic> ? PathResult.fromJson(p) : null;
    }

    return CompareResult(
      id: id,
      target: json['target'] as String? ?? '',
      ip: json['ip'] as String? ?? '',
      method: json['method'] as String? ?? '',
      done: json['done'] as bool? ?? false,
      error: json['error'] as String? ?? '',
      direct: path('direct'),
      vpn: path('vpn'),
    );
  }
}

/// Запрос `req-<id>.json`.
class CompareRequest {
  const CompareRequest({
    required this.id,
    required this.target,
    required this.port,
    required this.count,
    required this.created,
  });

  final String id;
  final String target;
  final int port;
  final int count;

  /// Миллисекунды с начала эпохи.
  final int created;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'id': id,
    'target': target,
    'port': port,
    'count': count,
    'created': created,
  };
}

/// Числа по замерам одной дороги.
class PathStats {
  const PathStats({required this.total, required this.failed, this.median, this.jitter});

  /// Всего замеров (с неудачами).
  final int total;
  final int failed;

  /// Медиана без неудач, мс; null — удачных замеров нет.
  final int? median;

  /// Разброс: среднее |Δ| соседних удачных замеров, мс; null — удачных меньше двух.
  final double? jitter;

  int get ok => total - failed;

  /// Неудачи в процентах, целое; null — замеров нет.
  int? get failPercent => total == 0 ? null : (failed * 100 / total).round();

  factory PathStats.of(List<int?> samples) {
    final ok = [for (final s in samples) ?s];
    int? median;
    if (ok.isNotEmpty) {
      final sorted = [...ok]..sort();
      final mid = sorted.length ~/ 2;
      median = sorted.length.isOdd ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2).round();
    }
    double? jitter;
    if (ok.length >= 2) {
      var sum = 0;
      for (var i = 1; i < ok.length; i++) {
        sum += (ok[i] - ok[i - 1]).abs();
      }
      jitter = sum / (ok.length - 1);
    }
    return PathStats(total: samples.length, failed: samples.length - ok.length, median: median, jitter: jitter);
  }
}

enum VerdictKind {
  /// Напрямую лучше.
  direct,

  /// Через VPN лучше.
  vpn,

  /// Почти одинаково.
  same,

  /// Сравнить нельзя (игры по UDP: через VPN только оценка).
  notComparable,

  /// Нечего сравнивать: одна из дорог не измерилась или обе не ответили.
  noData,
}

class CompareVerdict {
  const CompareVerdict(this.kind, this.text, {this.diffMs});

  final VerdictKind kind;

  /// Строка для экрана.
  final String text;

  /// На сколько мс одна дорога быстрее; null — решили неудачи или вывода нет.
  final int? diffMs;
}

/// Дорога «хуже», если неудач больше на столько процентных пунктов.
const failureGapPercent = 10;

/// «Одинаково»: разница меньше этой доли меньшей медианы...
const sameRelative = 0.15;

/// ...или меньше этого числа мс.
const sameAbsoluteMs = 10;

/// Вывод по правилам договора. Пока замеры идут (`done` = false) или была ошибка, вывода нет — null.
CompareVerdict? compareVerdict(CompareResult result) {
  if (!result.done || result.error.isNotEmpty) return null;
  final direct = result.direct;
  final vpn = result.vpn;
  if (direct == null || vpn == null) {
    return const CompareVerdict(VerdictKind.noData, 'Сравнить не удалось: ядро не вернуло замеры по обеим дорогам');
  }
  if (direct.estimate || vpn.estimate) {
    // Оценка качества туннеля — не замер цели: сравнивать с ней нечего.
    final median = direct.stats.median;
    final tail = median == null ? 'Прямой путь не ответил.' : 'Прямой путь: ${formatMs(median)}.';
    return CompareVerdict(VerdictKind.notComparable, 'Для игр по UDP сравнить нельзя. $tail');
  }
  if (!direct.available || !vpn.available) {
    final which = !direct.available && !vpn.available ? 'обе дороги' : (!direct.available ? 'напрямую' : 'через VPN');
    return CompareVerdict(VerdictKind.noData, 'Сравнить не удалось: измерить нельзя — $which');
  }
  final d = direct.stats;
  final v = vpn.stats;
  if (d.total == 0 || v.total == 0) {
    return const CompareVerdict(VerdictKind.noData, 'Сравнить не удалось: замеров нет');
  }

  // 1) Неудачи: доли сравниваем без дробей (failed/total), порог — failureGapPercent п.п.
  final gap = 100 * (v.failed * d.total - d.failed * v.total); // больше нуля: через VPN неудач больше
  final limit = failureGapPercent * d.total * v.total;
  if (gap >= limit) {
    return CompareVerdict(
      VerdictKind.direct,
      'Лучше напрямую: через VPN чаще неудачи (${v.failPercent} % против ${d.failPercent} %)',
    );
  }
  if (-gap >= limit) {
    return CompareVerdict(
      VerdictKind.vpn,
      'Лучше через VPN: напрямую чаще неудачи (${d.failPercent} % против ${v.failPercent} %)',
    );
  }

  // 2) Медианы.
  final dm = d.median;
  final vm = v.median;
  if (dm == null || vm == null) {
    return const CompareVerdict(VerdictKind.noData, 'Ни одна дорога не ответила. Проверьте адрес');
  }
  final diff = (dm - vm).abs();
  if (diff < sameAbsoluteMs || diff < math.min(dm, vm) * sameRelative) {
    return const CompareVerdict(VerdictKind.same, 'Разницы почти нет', diffMs: 0);
  }
  return dm < vm
      ? CompareVerdict(VerdictKind.direct, 'Лучше напрямую: на ${formatMs(diff)} быстрее', diffMs: diff)
      : CompareVerdict(VerdictKind.vpn, 'Лучше через VPN: на ${formatMs(diff)} быстрее', diffMs: diff);
}

/// «41 мс», от секунды — «1,2 с».
String formatMs(num ms) {
  final rounded = ms.round();
  if (rounded < 1000) return '$rounded мс';
  final s = (rounded / 1000).toStringAsFixed(1).replaceFirst('.', ',').replaceFirst(RegExp(r',0$'), '');
  return '$s с';
}
