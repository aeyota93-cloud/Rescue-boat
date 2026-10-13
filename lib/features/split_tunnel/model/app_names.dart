/// Шлюпка: понятные названия программ в туннеле — «PUBG», а не «TslGame». Сначала свой справочник
/// (игры, лаунчеры, античиты — у них в свойствах файла часто служебное имя), потом описание из
/// свойств запущенного файла, потом имя файла без «.exe».
library;

const _known = <String, String>{
  'cs2.exe': 'Counter-Strike 2',
  'dota2.exe': 'Dota 2',
  'destiny2.exe': 'Destiny 2',
  'escapefromtarkov.exe': 'Escape from Tarkov',
  'fortniteclient-win64-shipping.exe': 'Fortnite',
  'gta5.exe': 'GTA V',
  'minecraft.windows.exe': 'Minecraft',
  'overwatch.exe': 'Overwatch',
  'r5apex.exe': 'Apex Legends',
  'rainbowsix.exe': 'Rainbow Six Siege',
  'rustclient.exe': 'Rust',
  'tslgame.exe': 'PUBG',
  'valorant-win64-shipping.exe': 'Valorant',
  'worldoftanks.exe': 'World of Tanks',
  'worldofwarships.exe': 'World of Warships',
  'marvel-win64-shipping.exe': 'Marvel Rivals',
  'marvel.exe': 'Marvel Rivals: запуск',
  'beservice.exe': 'BattlEye',
  'easyanticheat.exe': 'Easy Anti-Cheat',
  'easyanticheat_eos.exe': 'Easy Anti-Cheat (Epic)',
  'vgc.exe': 'Vanguard (Riot)',
  'steam.exe': 'Steam',
  'steamservice.exe': 'Steam: служба',
  'steamwebhelper.exe': 'Steam: окно магазина',
  'gameoverlayui64.exe': 'Steam: оверлей',
  'epicgameslauncher.exe': 'Epic Games',
  'epicwebhelper.exe': 'Epic: окно магазина',
  'eadesktop.exe': 'EA app',
  'eabackgroundservice.exe': 'EA: служба',
  'battle.net.exe': 'Battle.net',
  'galaxyclient.exe': 'GOG Galaxy',
  'ubisoftconnect.exe': 'Ubisoft Connect',
  'upc.exe': 'Ubisoft: служба',
  'wgc.exe': 'Wargaming Game Center',
  'lgc.exe': 'Lesta Game Center',
  'league of legends.exe': 'League of Legends',
  'leagueclient.exe': 'League: клиент',
  'leagueclientux.exe': 'League: окно',
  'leagueclientuxrender.exe': 'League: окно (отрисовка)',
  'riot client.exe': 'Riot Client',
  'riotclientservices.exe': 'Riot: служба',
  'riotclientux.exe': 'Riot: окно',
  'riotclientcrashhandler.exe': 'Riot: отчёты о сбоях',
  'gamingservices.exe': 'Xbox Gaming Services',
  'gamingservicesnet.exe': 'Xbox Gaming Services: сеть',
  'gameinputredistservice.exe': 'Game Input',
  'nvidia overlay.exe': 'NVIDIA оверлей',
  'discord.exe': 'Discord',
  'telegram.exe': 'Telegram',
  'chrome.exe': 'Google Chrome',
  'msedge.exe': 'Microsoft Edge',
  'firefox.exe': 'Firefox',
  'browser.exe': 'Яндекс Браузер',
  'spotify.exe': 'Spotify',
  'vpnagent.exe': 'Cisco AnyConnect',
  'ssh.exe': 'SSH',
  'svchost.exe': 'Службы Windows',
};

/// Название программы [exe]. [described] — описания из свойств запущенных файлов
/// (ключ — имя файла в нижнем регистре).
String appTitle(String exe, [Map<String, String> described = const {}]) {
  if (exe.isEmpty) return 'Неизвестная программа';
  final key = exe.toLowerCase();
  final known = _known[key];
  if (known != null) return known;
  final d = described[key]?.trim() ?? '';
  if (d.isNotEmpty) return d;
  return exe.replaceFirst(RegExp(r'\.exe$', caseSensitive: false), '');
}
