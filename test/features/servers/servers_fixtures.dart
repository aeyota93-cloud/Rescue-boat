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
