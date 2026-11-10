import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

/// Подписка как у PasarGuard: основной, запасной XHTTP, Hysteria2 для игр; плюс группа.
/// Ядро отдаёт их отсортированными по пингу — порядок подписки в [threeServersOrder].
OutboundGroup threeServers({String selected = 'NL', int gamesDelay = 70000}) => OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: selected,
  items: [
    OutboundInfo(tag: 'balance', type: 'balancer', isGroup: true, tagDisplay: 'Балансировщик'),
    OutboundInfo(tag: 'NL игры', type: 'hysteria2', urlTestDelay: gamesDelay, tagDisplay: '🇳🇱 NL игры'),
    OutboundInfo(tag: 'NL', type: 'vless', urlTestDelay: 90, tagDisplay: '🇳🇱 NL', host: 'nl.example'),
    OutboundInfo(tag: 'NL запасной', type: 'vless', urlTestDelay: 120, tagDisplay: '🇳🇱 NL запасной'),
  ],
);

const threeServersOrder = ['balance', 'NL', 'NL запасной', 'NL игры'];

/// Шесть дорог одного протокола, имена из подписки (после пересборки серверов, 0.2.5).
const sixNames = [
  'Сервер 2',
  'Сервер 1',
  'Сервер 2 через РФ',
  'Сервер 1 через РФ',
  'Сервер 2 через РФ и VPN',
  'Сервер 1 через РФ и VPN',
];

OutboundGroup sixServers({String selected = 'Сервер 2'}) => OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: selected,
  items: [
    for (final (i, n) in sixNames.indexed)
      OutboundInfo(tag: n, type: 'vless', urlTestDelay: 80 + i * 20, tagDisplay: n),
  ],
);
