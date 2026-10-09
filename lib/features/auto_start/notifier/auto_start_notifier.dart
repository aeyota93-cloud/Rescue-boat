import 'dart:async';
import 'dart:io';

import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auto_start_notifier.g.dart';

@Riverpod(keepAlive: true)
class AutoStartNotifier extends _$AutoStartNotifier with InfraLogger {
  Timer? _timer;

  // Шлюпка: на Windows автозапуск — задача планировщика \RescueBoat\Autostart с правами
  // администратора (режим VPN без них не работает). Скрипт кладёт установщик рядом с программой;
  // в портативной версии его нет, тогда как у Hiddify — ключ Run в реестре.
  File get _tasksScript => File('${File(Platform.resolvedExecutable).parent.path}\\rescueboat-tasks.ps1');

  bool get _useTasks => Platform.isWindows && _tasksScript.existsSync();

  Future<String> _runTasks(String action) async {
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-WindowStyle',
      'Hidden',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      _tasksScript.path,
      '-Action',
      action,
    ]);
    if (result.exitCode != 0) {
      throw Exception('rescueboat-tasks.ps1 $action: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  // Проверка без запуска PowerShell (иначе раз в 15 минут мелькало бы окно): планировщик
  // хранит задачу файлом %SystemRoot%\System32\Tasks\RescueBoat\Autostart.
  Future<bool> _isEnabled() async {
    if (_useTasks) {
      final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      try {
        return File('$root\\System32\\Tasks\\RescueBoat\\Autostart').existsSync();
      } on FileSystemException {
        return false;
      }
    }
    return launchAtStartup.isEnabled();
  }

  @override
  Future<bool> build() async {
    if (!PlatformUtils.isDesktop) return false;
    final appInfo = ref.watch(appInfoProvider).requireValue;
    launchAtStartup.setup(
      appName: appInfo.name,
      appPath: Platform.resolvedExecutable,
      packageName: "RescueBoat",
    );
    final isEnabled = await _isEnabled();
    loggy.info("auto start is [${isEnabled ? "Enabled" : "Disabled"}]");
    _startTimer();
    ref.onDispose(() => _timer?.cancel());
    return isEnabled;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (timer) => updateStatus());
  }

  Future<bool> updateStatus() async {
    loggy.debug("update auto start status");
    final isEnabled = await _isEnabled();
    state = AsyncValue.data(isEnabled);
    return isEnabled;
  }

  Future<void> enable() async {
    loggy.debug("enabling auto start");
    if (_useTasks) {
      await _runTasks('enable-autostart');
    } else {
      await launchAtStartup.enable();
    }
    state = AsyncValue.data(await _isEnabled());
  }

  Future<void> disable() async {
    loggy.debug("disabling auto start");
    if (_useTasks) {
      await _runTasks('disable-autostart');
    } else {
      await launchAtStartup.disable();
    }
    state = AsyncValue.data(await _isEnabled());
  }
}
