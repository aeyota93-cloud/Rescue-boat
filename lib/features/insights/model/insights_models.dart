/// Шлюпка: ошибки соединений и здоровье подключения (редизайн 0.2.0).
///
/// Формат файлов ядра и формула оценки — docs/redesign/contract.md. Здесь только модели;
/// чтение файлов и подсчёт — в notifier/ (агент B), экраны — D1/D2.
library;

/// Период для списков ошибок.
enum InsightsPeriod {
  hour('Час', Duration(hours: 1)),
  day('Сутки', Duration(days: 1)),
  week('Неделя', Duration(days: 7));

  const InsightsPeriod(this.title, this.duration);
  final String title;
  final Duration duration;
}

/// Вид ошибки из errors-*.jsonl.
enum ErrorKind {
  timeout('время ожидания истекло'),
  reset('соединение сброшено'),
  refused('соединение отклонено'),
  dns('адрес не найден (DNS)'),
  tls('ошибка шифрования (TLS)'),
  eof('соединение закрылось сразу'),
  stall('замирание связи'),
  other('другая ошибка'),
  suppressed('слишком много ошибок, часть пропущена');

  const ErrorKind(this.title);

  /// Подпись для людей.
  final String title;

  static ErrorKind parse(String? s) => ErrorKind.values.firstWhere((k) => k.name == s, orElse: () => ErrorKind.other);
}

/// Куда шло соединение.
enum ErrorRoute {
  vpn('VPN', 'через VPN'),
  direct('мимо', 'мимо VPN'),
  block('блок', 'заблокировано');

  const ErrorRoute(this.short, this.long);
  final String short;
  final String long;

  static ErrorRoute parse(String? s) => ErrorRoute.values.firstWhere((r) => r.name == s, orElse: () => ErrorRoute.vpn);
}

class ErrorEvent {
  const ErrorEvent({
    required this.time,
    required this.kind,
    this.app = '',
    this.host = '',
    this.ip = '',
    this.port = 0,
    this.network = '',
    this.route = ErrorRoute.vpn,
    this.durationMs = 0,
    this.gapMs = 0,
    this.count = 1,
    this.message = '',
  });

  final DateTime time;
  final ErrorKind kind;

  /// Имя exe без пути, пусто — неизвестно.
  final String app;

  /// Домен, пусто — неизвестен.
  final String host;
  final String ip;
  final int port;
  final String network;
  final ErrorRoute route;
  final int durationMs;
  final int gapMs;

  /// Сколько одинаковых событий схлопнуто в одно.
  final int count;
  final String message;

  /// Сайт, если известен, иначе «ip:port».
  String get target => host.isNotEmpty ? host : (ip.isEmpty ? '' : '$ip:$port');

  /// null — строка не похожа на запись об ошибке.
  static ErrorEvent? tryParse(Map<String, dynamic> json) {
    final t = json['t'];
    if (t is! num) return null;
    return ErrorEvent(
      time: DateTime.fromMillisecondsSinceEpoch(t.toInt()),
      kind: ErrorKind.parse(json['kind'] as String?),
      app: json['app'] as String? ?? '',
      host: json['host'] as String? ?? '',
      ip: json['ip'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 0,
      network: json['net'] as String? ?? '',
      route: ErrorRoute.parse(json['route'] as String?),
      durationMs: (json['dur_ms'] as num?)?.toInt() ?? 0,
      gapMs: (json['gap_ms'] as num?)?.toInt() ?? 0,
      count: (json['n'] as num?)?.toInt() ?? 1,
      message: json['msg'] as String? ?? '',
    );
  }
}

/// Ошибки, сгруппированные по сайту (или по программе, если сайт неизвестен).
class ErrorGroup {
  const ErrorGroup({
    required this.key,
    required this.target,
    required this.app,
    required this.route,
    required this.count,
    required this.last,
    required this.events,
  });

  final String key;
  final String target;
  final String app;
  final ErrorRoute route;

  /// С учётом ErrorEvent.count.
  final int count;
  final DateTime last;

  /// Новые сверху.
  final List<ErrorEvent> events;
}

/// Одна строка «Здоровья»: оценка, полоска хорошо/средне/плохо и подпись-факт.
class HealthMetric {
  const HealthMetric({
    required this.title,
    required this.score,
    required this.good,
    required this.fair,
    required this.poor,
    required this.caption,
    this.trend = 0,
  });

  final String title;

  /// 0–100, null — нет данных.
  final int? score;

  /// Доли минут окна (сумма ≈ 1).
  final double good;
  final double fair;
  final double poor;
  final String caption;

  /// Изменение к прошлым суткам, в пунктах.
  final int trend;
}

class HealthSnapshot {
  const HealthSnapshot({
    required this.overall,
    required this.ping,
    required this.stability,
    required this.errorsFree,
    required this.dns,
    required this.pingMs,
    required this.jitterMs,
    required this.lossPercent,
  });

  final HealthMetric overall;
  final HealthMetric ping;
  final HealthMetric stability;
  final HealthMetric errorsFree;
  final HealthMetric dns;

  /// Сырые значения за окно (медиана пинга, ст. отклонение, % потерь), null — нет данных.
  final int? pingMs;
  final int? jitterMs;
  final double? lossPercent;

  bool get isEmpty => overall.score == null;

  List<HealthMetric> get metrics => [overall, ping, stability, errorsFree, dns];

  static const _none = HealthMetric(title: '', score: null, good: 0, fair: 0, poor: 0, caption: 'нет данных');

  static final empty = HealthSnapshot(
    overall: _titled('Общая оценка'),
    ping: _titled('Пинг до сервера'),
    stability: _titled('Стабильность'),
    errorsFree: _titled('Соединения без ошибок'),
    dns: _titled('DNS'),
    pingMs: null,
    jitterMs: null,
    lossPercent: null,
  );

  static HealthMetric _titled(String title) => HealthMetric(
    title: title,
    score: _none.score,
    good: 0,
    fair: 0,
    poor: 0,
    caption: _none.caption,
  );
}

/// Оценка за один день — точка на графике «Оценка по дням».
class DailyHealth {
  const DailyHealth({required this.day, required this.score, required this.errors, required this.outageMinutes});

  final DateTime day;

  /// null — в этот день замеров не было.
  final int? score;
  final int errors;

  /// Минуты, когда все vpn-замеры терялись (сервер недоступен).
  final int outageMinutes;
}
