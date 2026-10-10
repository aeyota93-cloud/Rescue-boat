import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/rescue_ui/widgets/power_button.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: состояние VPN для Главной, карточки статуса в меню и строки в меню трея.
class VpnStatus {
  const VpnStatus({
    required this.connected,
    required this.busy,
    required this.label,
    required this.canToggle,
    this.server = '',
    this.delayMs,
  });

  /// Положение переключателя.
  final bool connected;

  /// Идёт подключение или отключение.
  final bool busy;

  /// «Подключено · Нидерланды · 48 мс», «Отключено».
  final String label;

  /// Можно ли сейчас нажать (не во время переключения).
  final bool canToggle;

  /// Имя текущего сервера из ядра («Нидерланды»); пусто — неизвестно.
  final String server;

  /// Пинг текущего сервера, если ядро его уже замерило.
  final int? delayMs;

  /// Подключено и сервер отвечает.
  bool get on => connected && !busy;

  /// Состояние круглой кнопки питания.
  PowerState get power => busy
      ? PowerState.connecting
      : connected
      ? PowerState.on
      : PowerState.off;

  /// Коротко для карточки в меню: «Подключено», «Подключение…», «Отключено».
  String get title => on ? 'Подключено' : label;

  /// Подпись кнопки питания для чтеца: что случится по нажатию (или что идёт сейчас).
  String get powerLabel => !canToggle
      ? label
      : connected
      ? 'Отключить VPN'
      : 'Подключить VPN';
}

/// Пинг сервера, если он настоящий (ядро пишет 0 или 65000+, пока замера нет).
int? validDelay(int? delay) => delay != null && delay > 0 && delay < 65000 ? delay : null;

/// [withServer] — добавить имя сервера в подпись (на Главной); в трее только пинг.
VpnStatus vpnStatusOf(AsyncValue<ConnectionStatus> connection, OutboundInfo? proxy, {bool withServer = true}) {
  final delay = validDelay(proxy?.urlTestDelay);
  final server = (proxy?.tagDisplay ?? '').trim();
  final shown = withServer ? server : '';
  return switch (connection) {
    // Подключено, но сервер ещё ни разу не ответил — для людей это всё ещё «Подключение…».
    AsyncData(value: Connected()) when delay == null => VpnStatus(
      connected: true,
      busy: true,
      label: 'Подключение…',
      canToggle: true,
      server: server,
    ),
    AsyncData(value: Connected()) => VpnStatus(
      connected: true,
      busy: false,
      label: ['Подключено', if (shown.isNotEmpty) shown, '$delay мс'].join(' · '),
      canToggle: true,
      server: server,
      delayMs: delay,
    ),
    AsyncData(value: Connecting()) => const VpnStatus(
      connected: true,
      busy: true,
      label: 'Подключение…',
      canToggle: false,
    ),
    AsyncData(value: Disconnecting()) => const VpnStatus(
      connected: false,
      busy: true,
      label: 'Отключение…',
      canToggle: false,
    ),
    AsyncData(value: Disconnected(:final connectionFailure)) => VpnStatus(
      connected: false,
      busy: false,
      label: connectionFailure != null ? 'Не удалось подключиться' : 'Отключено',
      canToggle: true,
    ),
    AsyncError() => const VpnStatus(connected: false, busy: false, label: 'Не удалось подключиться', canToggle: true),
    _ => const VpnStatus(connected: false, busy: false, label: 'Отключено', canToggle: false),
  };
}

final vpnStatusProvider = Provider.autoDispose<VpnStatus>(
  (ref) => vpnStatusOf(ref.watch(connectionNotifierProvider), ref.watch(activeProxyNotifierProvider).valueOrNull),
);

/// Когда приложение увидело, что VPN подключился; null — сейчас не подключено.
///
/// Ядро время подключения не отдаёт, поэтому считаем сами: с момента, когда состояние
/// стало «Подключено». Живёт всё время работы приложения (его держит каркас).
final vpnConnectedSinceProvider = NotifierProvider<VpnConnectedSince, DateTime?>(VpnConnectedSince.new);

class VpnConnectedSince extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    ref.listen(connectionNotifierProvider, (_, next) {
      final connected = next.valueOrNull is Connected;
      if (connected && state == null) state = DateTime.now();
      if (!connected) state = null;
    });
    return ref.read(connectionNotifierProvider).valueOrNull is Connected ? DateTime.now() : null;
  }
}

/// «01:24:10» — сколько длится подключение.
String elapsedText(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(s ~/ 3600)}:${two(s % 3600 ~/ 60)}:${two(s % 60)}';
}
