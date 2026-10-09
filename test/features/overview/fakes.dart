import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/rescue_ui/rescue_theme.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Подменённые провайдеры для экранов Обзора и Ошибок: без ядра, файлов и настроек.

class FakeConnection extends ConnectionNotifier {
  FakeConnection(this.status);

  final ConnectionStatus status;
  int toggles = 0;

  @override
  Stream<ConnectionStatus> build() => Stream.value(status);

  @override
  Future<void> toggleConnection() async => toggles++;
}

class FakeActiveProxy extends ActiveProxyNotifier {
  FakeActiveProxy(this.info);

  final OutboundInfo info;

  @override
  Stream<OutboundInfo> build() => Stream.value(info);
}

class FakeActiveProfile extends ActiveProfile {
  FakeActiveProfile(this.profile);

  final ProfileEntity? profile;

  @override
  Stream<ProfileEntity?> build() => Stream.value(profile);
}

class FakeDialogs extends DialogNotifier {
  int notices = 0;

  @override
  Future<bool> showExperimentalFeatureNotice() async {
    notices++;
    return true;
  }
}

/// Списки туннеля только в памяти (настоящий пишет файлы наборов правил).
class FakeSplitTunnel extends SplitTunnelNotifier {
  FakeSplitTunnel([this.initial = const SplitTunnel()]);

  final SplitTunnel initial;

  @override
  SplitTunnel build() => initial;

  @override
  void add(SplitTarget target, SplitKind kind, String value) {
    state = state
        .withList(target.other, state.list(target.other).without(kind, value))
        .withList(target, state.list(target).withItem(kind, value));
  }
}

final now = DateTime.now();

ErrorEvent event(
  Duration ago,
  ErrorKind kind, {
  String app = '',
  String host = '',
  String ip = '',
  ErrorRoute route = ErrorRoute.vpn,
  int count = 1,
  String message = '',
}) => ErrorEvent(
  time: now.subtract(ago),
  kind: kind,
  app: app,
  host: host,
  ip: ip,
  port: ip.isEmpty ? 0 : 443,
  route: route,
  count: count,
  message: message,
);

/// Новые сверху, как отдаёт errorEventsProvider.
final sampleEvents = [
  event(
    const Duration(minutes: 3),
    ErrorKind.reset,
    app: 'chrome.exe',
    host: 'kinopoisk.ru',
    ip: '213.180.204.211',
    count: 3,
    message: 'read: connection reset by peer',
  ),
  event(const Duration(minutes: 20), ErrorKind.stall, app: 'Discord.exe', host: 'gateway.discord.gg'),
  event(const Duration(minutes: 40), ErrorKind.timeout, app: 'chrome.exe', host: 'kinopoisk.ru', ip: '213.180.193.230'),
  event(
    const Duration(hours: 3),
    ErrorKind.timeout,
    app: 'steam.exe',
    ip: '23.62.214.9',
    route: ErrorRoute.direct,
    message: 'dial tcp: i/o timeout',
  ),
  event(
    const Duration(hours: 5),
    ErrorKind.dns,
    app: 'browser.exe',
    host: 'api.example-shop.ru',
    route: ErrorRoute.direct,
  ),
];

List<ErrorEvent> eventsFor(InsightsPeriod p) => [
  for (final e in sampleEvents)
    if (now.difference(e.time) <= p.duration) e,
];

HealthMetric metric(String title, int score, String caption, {int trend = 0}) =>
    HealthMetric(title: title, score: score, good: 0.8, fair: 0.14, poor: 0.06, caption: caption, trend: trend);

final sampleHealth = HealthSnapshot(
  overall: metric('Общая оценка', 92, 'по пяти показателям', trend: 3),
  ping: metric('Пинг до сервера', 95, '48 мс, обычно 45–60'),
  stability: metric('Стабильность', 81, 'потерь 1%', trend: -4),
  errorsFree: metric('Соединения без ошибок', 97, '3% соединений с ошибкой', trend: 1),
  dns: metric('DNS', 100, 'все адреса находятся'),
  pingMs: 48,
  jitterMs: 6,
  lossPercent: 1,
);

final sampleHistory = [
  for (var i = 0; i < 30; i++)
    DailyHealth(
      day: DateTime(now.year, now.month, now.day - 29 + i),
      score: i < 3 ? null : (i == 12 ? 74 : (i == 20 ? 85 : 91)),
      errors: i == 20 ? 4 : 0,
      outageMinutes: i == 12 ? 40 : 0,
    ),
];

final emptyHistory = [
  for (var i = 0; i < 30; i++)
    DailyHealth(day: DateTime(now.year, now.month, now.day - 29 + i), score: null, errors: 0, outageMinutes: 0),
];

final sampleProfile = ProfileEntity.remote(
  id: '1',
  active: true,
  name: 'Основной',
  url: 'https://sub.example.org/secret-token',
  lastUpdate: now,
  subInfo: SubscriptionInfo(
    upload: 8 * 1073741824,
    download: 40 * 1073741824,
    total: 200 * 1073741824,
    expire: now.add(const Duration(days: 30)),
  ),
);

/// Все подмены разом; любые можно заменить своими.
List<Override> pageOverrides({
  FakeConnection? connection,
  FakeSplitTunnel? split,
  FakeDialogs? dialogs,
  ProfileEntity? profile,
  OutboundInfo? proxy,
  bool empty = false,
}) => [
  connectionNotifierProvider.overrideWith(() => connection ?? FakeConnection(const Connected())),
  activeProxyNotifierProvider.overrideWith(
    () => FakeActiveProxy(proxy ?? OutboundInfo(urlTestDelay: 48, tagDisplay: 'Нидерланды')),
  ),
  activeProfileProvider.overrideWith(() => FakeActiveProfile(empty ? null : profile ?? sampleProfile)),
  dialogNotifierProvider.overrideWith(() => dialogs ?? FakeDialogs()),
  splitTunnelProvider.overrideWith(() => split ?? FakeSplitTunnel(SplitTunnel.defaults)),
  errorEventsProvider.overrideWith((ref, period) => AsyncData(empty ? const [] : eventsFor(period))),
  errorCountProvider.overrideWith(
    (ref, window) => empty
        ? 0
        : eventsFor(InsightsPeriod.values.firstWhere((p) => p.duration == window)).fold(0, (s, e) => s + e.count),
  ),
  healthProvider.overrideWith((ref) => AsyncData(empty ? HealthSnapshot.empty : sampleHealth)),
  healthHistoryProvider.overrideWith((ref) => AsyncData(empty ? emptyHistory : sampleHistory)),
];

void setWindowSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Страница в приложении с темой Шлюпки; ждём, пока потоки подменённых провайдеров отдадут значения.
Future<void> pumpPage(
  WidgetTester tester,
  Widget page, {
  required List<Override> overrides,
  Size size = const Size(1440, 1000),
}) async {
  setWindowSize(tester, size);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: RescueTheme.dark(),
        home: Scaffold(body: page),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}
