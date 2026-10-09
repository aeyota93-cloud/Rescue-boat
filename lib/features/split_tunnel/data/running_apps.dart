import 'dart:convert';
import 'dart:io';

/// Шлюпка: запущенная программа для выбора в раздельный туннель.
class RunningApp {
  const RunningApp({required this.exe, required this.path, required this.title});

  /// Имя файла, например «steam.exe» — по нему работает правило.
  final String exe;
  final String path;

  /// Описание из свойств файла («Steam») или имя без .exe.
  final String title;
}

/// Программы пользователя, которые сейчас запущены (без системных из папки Windows).
/// Без прав администратора часть путей Windows не отдаёт — такие программы пропускаются.
Future<List<RunningApp>> listRunningApps() async {
  if (!Platform.isWindows) return const [];
  const script = r'''
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Get-Process | Where-Object { $_.Path -and -not $_.Path.StartsWith($env:windir, 'OrdinalIgnoreCase') } |
  Select-Object @{n='path';e={$_.Path}}, @{n='title';e={$_.MainModule.FileVersionInfo.FileDescription}} -Unique |
  ConvertTo-Json -Compress
''';
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-WindowStyle',
    'Hidden',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    script,
  ], stdoutEncoding: utf8);
  final out = (result.stdout as String).trim();
  if (out.isEmpty) return const [];
  final decoded = jsonDecode(out);
  final items = decoded is List ? decoded : [decoded];
  final byExe = <String, RunningApp>{};
  for (final item in items.cast<Map<String, dynamic>>()) {
    final path = item['path'] as String? ?? '';
    if (path.isEmpty) continue;
    final exe = path.split(RegExp(r'[\\/]')).last;
    final description = (item['title'] as String? ?? '').trim();
    final title = description.isNotEmpty ? description : exe.replaceFirst(RegExp(r'\.exe$', caseSensitive: false), '');
    byExe.putIfAbsent(exe.toLowerCase(), () => RunningApp(exe: exe, path: path, title: title));
  }
  final apps = byExe.values.toList()..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return apps;
}
