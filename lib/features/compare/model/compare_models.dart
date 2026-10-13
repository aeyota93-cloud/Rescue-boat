/// Шлюпка: «Сравнить пути» — модели обмена с ядром и вычисление вывода.
/// Договор: docs/redesign/compare-paths.md. Без виджетов и файлов, чтобы проверять тестами.
library;

import 'dart:math' as math;

/// Одна дорога из ответа ядра (`paths.direct` / `paths.vpn` / элемент `paths.servers`).
class PathResult {
  const PathResult({
    this.tag = '',
    this.available = true,
    this.estimate = false,
    this.firstMs,
    this.samples = const [],
    this.note = '',
  });

  /// Тег сервера (только у `paths.servers`), иначе пусто.
  final String tag;

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
      tag: json['tag'] as String? ?? '',
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
    this.servers = const [],
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

  /// Каждый сервер `select` по своему выходу, в порядке подписки (ядро rb.16+, servers-v2.md).
  /// Пусто — старое ядро или в профиле один сервер: тогда сравниваем с [vpn], как раньше.
  final List<PathResult> servers;

  /// Сколько замеров по всем дорогам уже пришло.
  int get samplesDone =>
      (direct?.samples.length ?? 0) + (vpn?.samples.length ?? 0) + servers.fold(0, (sum, s) => sum + s.samples.length);

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

    final rawServers = paths is Map<String, dynamic> ? paths['servers'] : null;
    return CompareResult(
      id: id,
      target: json['target'] as String? ?? '',
      ip: json['ip'] as String? ?? '',
      method: json['method'] as String? ?? '',
      done: json['done'] as bool? ?? false,
      error: json['error'] as String? ?? '',
      direct: path('direct'),
      vpn: path('vpn'),
      servers: rawServers is List
          ? [
              for (final e in rawServers)
                if (e is Map<String, dynamic> && (e['tag'] as String? ?? '').isNotEmpty) PathResult.fromJson(e),
            ]
          : const [],
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

// ---------- v2: все дороги (docs/redesign/servers-v2.md) ----------

/// Дорога «напрямую» среди [CompareRoad.id]: у серверов id — их тег, а он пустым не бывает.
const directRoad = '';

/// Одна дорога в таблице v2: напрямую или сервер.
class CompareRoad {
  const CompareRoad(this.id, this.path);

  /// [directRoad] или тег сервера.
  final String id;
  final PathResult path;

  bool get direct => id == directRoad;
}

/// Дороги для таблицы: «Напрямую», затем серверы в порядке ответа (порядок `select`).
/// Пусто — ядро не прислало `servers`: показываем две дороги, как раньше.
List<CompareRoad> compareRoads(CompareResult result) => result.servers.isEmpty
    ? const []
    : [
        if (result.direct case final d?) CompareRoad(directRoad, d),
        for (final s in result.servers) CompareRoad(s.tag, s),
      ];

/// Сравнение двух дорог по правилу договора: -1 — [a] лучше, 1 — [b] лучше, 0 — одинаково,
/// null — сравнить нечем (замеров нет или обе не ответили).
int? compareStats(PathStats a, PathStats b) {
  if (a.total == 0 || b.total == 0) return null;
  // Неудачи: доли без дробей (failed/total), порог — failureGapPercent п.п.; больше нуля — у [a] неудач больше.
  final gap = 100 * (a.failed * b.total - b.failed * a.total);
  final limit = failureGapPercent * a.total * b.total;
  if (gap >= limit) return 1;
  if (-gap >= limit) return -1;
  final am = a.median;
  final bm = b.median;
  if (am == null || bm == null) return null;
  final diff = (am - bm).abs();
  if (diff < sameAbsoluteMs || diff < math.min(am, bm) * sameRelative) return 0;
  return am < bm ? -1 : 1;
}

enum RoadVerdictKind {
  /// Лучше другая дорога, чем сейчас (или «сейчас» неизвестно).
  change,

  /// Лучше всего — как сейчас, или лидеров несколько «одинаково» и среди них текущая.
  keep,

  /// Игры по UDP: серверы сравнены по качеству туннеля — вывод с оговоркой.
  estimate,

  /// Сравнить не удалось.
  noData,
}

class RoadVerdict {
  const RoadVerdict(this.kind, this.text, {this.best, this.bestServer, this.leaders = const {}});

  final RoadVerdictKind kind;
  final String text;

  /// Лучшая дорога ([directRoad] или тег); null — вывода нет.
  final String? best;

  /// Лучший из серверов — для кнопки «Пустить через «…»» (даже если лучше напрямую).
  final String? bestServer;

  /// Все дороги, которые никем не побиты («одинаково» между собой).
  final Set<String> leaders;
}

/// Лучшая дорога v2: правило [compareStats] ко всем дорогам; лидеры — те, кого никто не побил.
/// Если лидеров несколько и среди них текущая [current] — лучшей считается она (не дёргаем без
/// пользы). [serverName] — имя сервера по тегу в середине фразы («запасной 2»).
/// null — замеры ещё идут, была ошибка или ядро не прислало `servers`.
RoadVerdict? roadVerdict(CompareResult result, {String? current, required String Function(String tag) serverName}) {
  if (!result.done || result.error.isNotEmpty) return null;
  String phrase(String id) => id == directRoad ? 'напрямую' : 'через ${serverName(id)}';
  final roads = compareRoads(result);
  if (roads.isEmpty) return null;

  String? pick(List<CompareRoad> candidates, Set<String> leaders) {
    if (leaders.isEmpty) return null;
    if (current != null && leaders.contains(current)) return current;
    final sorted = candidates.where((r) => leaders.contains(r.id)).toList()
      ..sort((a, b) {
        final byFail = a.path.stats.failed * b.path.stats.total - b.path.stats.failed * a.path.stats.total;
        if (byFail != 0) return byFail;
        return (a.path.stats.median ?? 1 << 30).compareTo(b.path.stats.median ?? 1 << 30);
      });
    return sorted.first.id;
  }

  Set<String> leadersOf(List<CompareRoad> candidates) => {
    for (final r in candidates)
      if (!candidates.any((o) => o != r && compareStats(o.path.stats, r.path.stats) == -1)) r.id,
  };

  bool measured(CompareRoad r) => r.path.stats.total > 0 && r.path.stats.ok > 0;

  final servers = roads.where((r) => !r.direct).toList();
  if (servers.any((r) => r.path.estimate)) {
    // Оценка качества туннеля — не замер цели: с прямым путём не сравниваем, только серверы между собой.
    final candidates = servers.where(measured).toList();
    final best = pick(candidates, leadersOf(candidates));
    if (best == null) {
      final median = result.direct?.stats.median;
      final tail = median == null ? 'Прямой путь не ответил.' : 'Прямой путь: ${formatMs(median)}.';
      return RoadVerdict(RoadVerdictKind.noData, 'Для игр по UDP сравнить нельзя. $tail');
    }
    return RoadVerdict(
      RoadVerdictKind.estimate,
      'Для игры точно покажет только сама игра; по качеству дороги лучше всего — ${serverName(best)}',
      best: best,
      bestServer: best,
    );
  }

  final candidates = roads.where((r) => r.path.available && r.path.stats.total > 0).toList();
  if (candidates.length < 2 || !candidates.any(measured)) {
    return const RoadVerdict(RoadVerdictKind.noData, 'Сравнить не удалось: измерить удалось меньше двух дорог');
  }
  final leaders = leadersOf(candidates);
  final best = pick(candidates, leaders);
  if (best == null) return const RoadVerdict(RoadVerdictKind.noData, 'Ни одна дорога не ответила. Проверьте адрес');
  final serverCandidates = candidates.where((r) => !r.direct).toList();
  final bestServer = best != directRoad ? best : pick(serverCandidates, leadersOf(serverCandidates));

  if (best == current) {
    return RoadVerdict(
      RoadVerdictKind.keep,
      leaders.length > 1 ? 'Разницы почти нет — лучше оставить как есть' : 'Лучше всего — как сейчас, ${phrase(best)}',
      best: best,
      bestServer: bestServer,
      leaders: leaders,
    );
  }

  // Насколько лучше, чем сейчас (если «сейчас» известно и измерено).
  var why = '';
  final now = current == null ? null : candidates.where((r) => r.id == current).firstOrNull;
  final winner = candidates.firstWhere((r) => r.id == best);
  if (now != null && compareStats(winner.path.stats, now.path.stats) == -1) {
    final a = winner.path.stats;
    final b = now.path.stats;
    final byFailures = 100 * (b.failed * a.total - a.failed * b.total) >= failureGapPercent * a.total * b.total;
    if (byFailures) {
      why = ': сейчас чаще неудачи (${b.failPercent} % против ${a.failPercent} %)';
    } else if (a.median != null && b.median != null) {
      why = ': на ${formatMs(b.median! - a.median!)} быстрее, чем сейчас';
    }
  }
  return RoadVerdict(
    RoadVerdictKind.change,
    'Лучше ${phrase(best)}$why',
    best: best,
    bestServer: bestServer,
    leaders: leaders,
  );
}
