/// Шлюпка: аргументы командной строки программы.
/// Задача планировщика \RescueBoat\Autostart запускает RescueBoat.exe с `--autostart`:
/// тогда окно не показывается, программа сразу в трее (windows/packaging/rescueboat-tasks.ps1).
List<String> launchArgs = const [];

bool get startedByAutostart => launchArgs.contains('--autostart');
