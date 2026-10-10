import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';

/// Шлюпка: витрина всех кирпичиков стиля «Д» на тестовых данных (только для отладки, маршрут /ui-gallery).
///
/// Сверху — мини-Главная как в макете docs/redesign/mockup/style-d-dark.html (для сверки),
/// ниже — куски остальных экранов и все кирпички по отдельности.
class RescueGalleryPage extends StatefulWidget {
  const RescueGalleryPage({super.key});

  @override
  State<RescueGalleryPage> createState() => _RescueGalleryPageState();
}

enum _Period { hour, day, week }

enum _Kind { all, app, site, ip }

enum _HomeTab { now, health }

enum _TunTab { all, bypass, vpn }

class _App {
  const _App(this.name, this.detail, this.letter, this.kind, this.online, this.errors);

  final String name;
  final String detail;
  final String letter;
  final String kind;
  final bool online;
  final int errors;
}

class _Group {
  const _Group(this.id, this.letter, this.target, this.sub, this.count);

  final String id;
  final String letter;
  final String target;
  final String sub;
  final int count;
}

class _RescueGalleryPageState extends State<RescueGalleryPage> {
  int _nav = 0;
  PowerState _power = PowerState.on;
  String _server = 'nl';
  _HomeTab _homeTab = _HomeTab.now;
  _TunTab _tunTab = _TunTab.all;
  _Period _period = _Period.day;
  _Kind _filter = _Kind.all;
  String _group = 'kino';
  bool _vpnMode = true;
  bool _connected = true;
  bool _checkbox = true;
  double _slider = 0.4;
  String _pill = 'auto';
  final _modes = <String, bool>{'Весь компьютер': true, 'Российские сайты напрямую': true, 'Игры мимо VPN': false};
  static const _modeHints = {
    'Весь компьютер': 'Все программы и игры',
    'Российские сайты напрямую': 'Банки и Госуслуги видят домашний IP',
    'Игры мимо VPN': 'Игры тоже через VPN',
  };
  final _switches = <String, bool>{
    'Запускать при входе в Windows': true,
    'Запускать свёрнутым': false,
    'Крестик сворачивает в трей': true,
  };
  static const _hints = [
    'Без окна «Разрешить изменения?»',
    'Сразу в трей у часов',
    'VPN не выключается при закрытии окна',
  ];
  final _routes = <String, RouteChoice>{
    'Google Chrome': RouteChoice.auto,
    'Telegram': RouteChoice.vpn,
    'Steam': RouteChoice.bypass,
    'kinopoisk.ru': RouteChoice.bypass,
  };

  static const _servers = [
    ServerOption(value: 'nl', code: 'NL', name: 'Нидерланды', subtitle: 'first.gym-notes.ru · Основная', ping: '48 МС'),
    ServerOption(value: 'auto', code: 'A', name: 'Автовыбор', subtitle: 'самый быстрый из рабочих', ping: 'АВТО'),
  ];

  static const _apps = [
    _App('Google Chrome', 'chrome.exe', 'G', 'Программа', true, 5),
    _App('Telegram', 'Telegram.exe', 'T', 'Программа', true, 0),
    _App('Steam', 'steam.exe · из списка игр', 'S', 'Программа', false, 1),
    _App('kinopoisk.ru', 'и все поддомены', 'K', 'Сайт', false, 5),
  ];

  static const _groups = [
    _Group('discord', 'D', 'gateway.discord.gg', 'Discord · обрывы · через VPN', 12),
    _Group('kino', 'K', 'kinopoisk.ru', 'Google Chrome · сброс · через VPN', 5),
    _Group('shop', 'E', 'api.example-shop.ru', 'Яндекс Браузер · DNS · мимо', 3),
  ];

  bool get _on => _power == PowerState.on;

  void _togglePower() => setState(() => _power = _on ? PowerState.off : PowerState.on);

  @override
  Widget build(BuildContext context) {
    final server = _servers.firstWhere((s) => s.value == _server);
    return Theme(
      data: RescueTheme.dark(),
      child: RescueShell(
        selectedIndex: _nav,
        onSelected: (i) => setState(() => _nav = i),
        items: const [
          RescueNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Главная'),
          RescueNavItem(icon: Icons.call_split_rounded, label: 'Раздельный туннель'),
          RescueNavItem(icon: Icons.warning_amber_rounded, label: 'Ошибки', count: 7),
          RescueNavItem(icon: Icons.dns_outlined, selectedIcon: Icons.dns_rounded, label: 'Подписки и серверы'),
        ],
        bottomItem: const RescueNavItem(icon: Icons.tune_rounded, label: 'Настройки'),
        footer: ShellStatusCard(
          state: _power,
          title: _on ? 'Подключено' : 'Отключено',
          subtitle: _on ? '${server.name} · ${server.ping?.toLowerCase()}' : 'нажмите кнопку',
          onPower: _togglePower,
        ),
        compactFooter: Center(
          child: PowerButton.mini(state: _power, onPressed: _togglePower),
        ),
        versionLabel: 'Версия 0.3.0 · основано на Hiddify',
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._home(server),
              const SizedBox(height: 36),
              ..._tunnel(),
              const SizedBox(height: 36),
              ..._errors(),
              const SizedBox(height: 36),
              ..._serversScreen(),
              const SizedBox(height: 36),
              ..._settings(),
              const SizedBox(height: 36),
              ..._misc(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Главная ────────────────────────────────────────────────────────────────────────────

  List<Widget> _home(ServerOption<String> server) {
    final power = Column(
      children: [
        PowerButton(state: _power, onPressed: _togglePower),
        const SizedBox(height: 14),
        Text(_on ? 'Подключено' : 'Отключено', style: RescueText.statusLight.copyWith(color: RescueColors.onAccent)),
        const SizedBox(height: 4),
        Text(
          _on ? '01:24:10 · ${server.name} · ваш IP скрыт' : 'Нажмите на кнопку, чтобы подключиться',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: RescueColors.onAccentMuted),
        ),
      ],
    );
    final picker = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Сервер'),
        const SizedBox(height: 10),
        ServerSelect<String>(
          options: _servers,
          value: _server,
          onChanged: (v) => setState(() => _server = v),
          onAdd: () => setState(() => _nav = 3),
        ),
        const SizedBox(height: 16),
        const SectionLabel('Режим'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in _modes.entries)
              ModeChip(
                label: e.key,
                selected: e.value,
                hint: _modeHints[e.key],
                onChanged: (v) => setState(() => _modes[e.key] = v),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _modes.entries.map((e) => e.value ? _modeHints[e.key] : 'выкл.').join(' · '),
          style: const TextStyle(fontSize: 12, color: RescueColors.onAccentMuted),
        ),
      ],
    );
    final rings = _homeTab == _HomeTab.now
        ? [
            RingStat(value: _on ? 0.35 : 0, label: _on ? '48' : '—', title: 'МС ПИНГ', caption: 'обычно 45–60'),
            RingStat(value: _on ? 0.15 : 0, label: _on ? '6' : '—', title: 'МС РАЗБРОС', caption: 'джиттер'),
            RingStat(value: _on ? 0.05 : 0, label: _on ? '1' : '—', title: '% ПОТЕРЬ', caption: 'за последний час'),
            const RingStat(value: 0.4, label: '7', title: 'ОШИБОК', caption: 'за час', color: RescueColors.warn),
          ]
        : const [
            RingStat(value: 0.92, label: '92', title: 'ОБЩАЯ', caption: 'всё в порядке'),
            RingStat(value: 0.95, label: '95', title: 'ПИНГ', caption: '48 мс'),
            RingStat(value: 0.81, label: '81', title: 'СТАБИЛЬНОСТЬ', caption: 'разброс 6 мс'),
            RingStat(value: 0.97, label: '97', title: 'БЕЗ ОШИБОК', caption: '3% с ошибкой'),
          ];
    final tabs = FolderTabs<_HomeTab>(
      semanticLabel: 'Сводка',
      tabs: [
        FolderTab(value: _HomeTab.now, title: 'Связь', badge: _on ? 'ВКЛ' : 'ВЫКЛ'),
        const FolderTab(value: _HomeTab.health, title: 'Здоровье', badge: '92'),
      ],
      value: _homeTab,
      onChanged: (t) => setState(() => _homeTab = t),
      inactiveForeground: RescueColors.onAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _homeTab == _HomeTab.now ? (_on ? 'Сейчас · ${server.name}' : 'VPN выключен') : 'За 24 часа',
            style: RescueText.smallSecondary,
          ),
          const SizedBox(height: 16),
          RescueGrid(minItemWidth: 150, runSpacing: 16, children: rings),
        ],
      ),
    );

    return [
      const SectionLabel.screen('Главная', trailing: Text('замеры раз в минуту', style: RescueText.caption)),
      const SizedBox(height: 20),
      RescueCard.accent(
        semanticLabel: 'Подключение',
        child: LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth >= 900) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 230, child: power),
                  const SizedBox(width: 28),
                  Expanded(flex: 30, child: picker),
                  const SizedBox(width: 28),
                  Expanded(flex: 36, child: tabs),
                ],
              );
            }
            if (c.maxWidth >= 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 230, child: power),
                      const SizedBox(width: 28),
                      Expanded(child: picker),
                    ],
                  ),
                  const SizedBox(height: 28),
                  tabs,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [power, const SizedBox(height: 28), picker, const SizedBox(height: 28), tabs],
            );
          },
        ),
      ),
      const SizedBox(height: 20),
      RescueGrid(
        minItemWidth: 300,
        spacing: 20,
        children: [
          DeepList(
            title: 'Ошибки за час',
            count: '7',
            actionLabel: 'Все ошибки',
            onAction: () => setState(() => _nav = 2),
            children: const [
              DeepListTile(
                leading: 'K',
                title: 'kinopoisk.ru',
                subtitle: 'Chrome · сброс · VPN',
                trailingText: '5',
                highlighted: true,
              ),
              DeepListTile(
                leading: 'D',
                title: 'gateway.discord.gg',
                subtitle: 'Discord · обрыв · VPN',
                trailingText: '1',
              ),
              DeepListTile(
                leading: 'S',
                title: 'cdn.steamstatic.com',
                subtitle: 'Steam · таймаут · мимо',
                trailingText: '1',
              ),
            ],
          ),
          RescueCard(
            semanticLabel: 'Раздельный туннель',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Раздельный туннель'),
                const SizedBox(height: 14),
                const StatColumns(
                  columns: [
                    StatColumn(label: 'МИМО VPN', value: '38'),
                    StatColumn(label: 'ЧЕРЕЗ VPN', value: '12'),
                    StatColumn(label: 'В СЕТИ', value: '4', lineColor: RescueColors.accent),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Списки важнее общих правил и действуют сразу, без переподключения.',
                  style: RescueText.smallSecondary,
                ),
                const SizedBox(height: 14),
                FilledButton(
                  style: RescueTheme.deepFilledButton(),
                  onPressed: () => setState(() => _nav = 1),
                  child: const Text('Открыть туннель'),
                ),
              ],
            ),
          ),
          RescueCard(
            semanticLabel: 'Подписка',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Подписка', trailing: RescueBadge(label: 'ДО 9 НОЯБРЯ')),
                const SizedBox(height: 12),
                const Text.rich(
                  TextSpan(
                    text: '48 ГБ ',
                    style: RescueText.bigLight,
                    children: [TextSpan(text: 'из 200', style: RescueText.smallSecondary)],
                  ),
                ),
                const SizedBox(height: 12),
                const RescueProgressBar(value: 0.24, color: RescueColors.deep),
                const SizedBox(height: 12),
                const Text('Основная · обновлена в 12:40', style: RescueText.caption),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => setState(() => _nav = 3), child: const Text('Подписки и серверы')),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  // ── Раздельный туннель ─────────────────────────────────────────────────────────────────

  List<Widget> _tunnel() {
    int count(RouteChoice r) => _routes.values.where((v) => v == r).length;
    final shown = _apps.where(
      (a) => switch (_tunTab) {
        _TunTab.all => true,
        _TunTab.bypass => _routes[a.name] == RouteChoice.bypass,
        _TunTab.vpn => _routes[a.name] == RouteChoice.vpn,
      },
    );
    return [
      SectionLabel.screen(
        'Раздельный туннель',
        trailing: FilledButton(onPressed: () {}, child: const Text('+ Добавить')),
      ),
      const SizedBox(height: 20),
      RescueGrid(
        children: [
          StatTile(label: 'Через VPN', value: '${count(RouteChoice.vpn)}', markerColor: RescueColors.accent),
          StatTile(label: 'Мимо VPN', value: '${count(RouteChoice.bypass)}', markerColor: RescueColors.text),
          StatTile(label: 'По общим правилам', value: '${count(RouteChoice.auto)}', markerColor: RescueColors.muted),
        ],
      ),
      const SizedBox(height: 20),
      FolderTabs<_TunTab>(
        semanticLabel: 'Списки',
        tabs: [
          FolderTab(value: _TunTab.all, title: 'Все', badge: '${_apps.length + 35}'),
          FolderTab(value: _TunTab.bypass, title: 'Мимо', badge: '${count(RouteChoice.bypass) + 35}'),
          FolderTab(value: _TunTab.vpn, title: 'Через VPN', badge: '${count(RouteChoice.vpn)}'),
        ],
        value: _tunTab,
        onChanged: (t) => setState(() => _tunTab = t),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const SizedBox(
              width: 320,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Найти программу, сайт или IP',
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                ),
              ),
            ),
            FilterChips<_Kind>(
              options: const [(_Kind.all, 'Всё'), (_Kind.app, 'Программы'), (_Kind.site, 'Сайты'), (_Kind.ip, 'IP')],
              selected: _filter,
              onSelected: (k) => setState(() => _filter = k),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 600;
          return DeepList(
            radius: 36,
            semanticLabel: 'Записи',
            children: [for (final (i, a) in shown.indexed) _tunnelRow(a, highlighted: i == 0, narrow: narrow)],
          );
        },
      ),
      const SizedBox(height: 12),
      const Text(
        '«Авто» — решают общие правила: российские сайты напрямую, остальное через VPN.',
        style: RescueText.caption,
      ),
    ];
  }

  Widget _tunnelRow(_App a, {required bool highlighted, required bool narrow}) {
    final route = RouteSwitch(
      value: _routes[a.name] ?? RouteChoice.auto,
      semanticLabel: 'Куда идёт ${a.name}',
      onAccent: highlighted,
      width: narrow ? null : 236,
      onChanged: (r) => setState(() => _routes[a.name] = r),
    );
    final tile = DeepListTile(
      leading: a.letter,
      title: a.name,
      subtitle: '${a.detail} · ${a.kind} · ${a.online ? 'в сети' : 'не в сети'}',
      highlighted: highlighted,
      tileSize: 38,
      radius: 22,
      minHeight: 64,
      trailing: narrow ? null : route,
    );
    if (!narrow) return tile;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [tile, const SizedBox(height: 6), route]);
  }

  // ── Ошибки ─────────────────────────────────────────────────────────────────────────────

  List<Widget> _errors() {
    final sel = _groups.firstWhere((g) => g.id == _group);
    return [
      SectionLabel.screen(
        'Ошибки соединений',
        trailing: PeriodSwitch<_Period>(
          options: const [(_Period.hour, 'Час'), (_Period.day, 'Сутки'), (_Period.week, 'Неделя')],
          value: _period,
          onChanged: (p) => setState(() => _period = p),
        ),
      ),
      const SizedBox(height: 20),
      RescueGrid(
        minItemWidth: 380,
        spacing: 20,
        children: [
          DeepList(
            title: 'По сайтам и программам',
            count: '${_groups.length}',
            radius: 36,
            children: [
              for (final g in _groups)
                DeepListTile(
                  leading: g.letter,
                  title: g.target,
                  subtitle: g.sub,
                  highlighted: g.id == _group,
                  minHeight: 68,
                  tileSize: 38,
                  radius: 22,
                  semanticLabel: '${g.target}, ${g.sub}, ${g.count} ошибок',
                  onTap: () => setState(() => _group = g.id),
                  trailing: RingStat(
                    value: (g.count / 12).clamp(0, 1),
                    label: '${g.count}',
                    size: 40,
                    strokeWidth: 3.5,
                    color: DeepTileColors.of(highlighted: g.id == _group).ring,
                    trackColor: DeepTileColors.of(highlighted: g.id == _group).ringTrack,
                    labelColor: DeepTileColors.of(highlighted: g.id == _group).foreground,
                  ),
                ),
            ],
          ),
          FolderTabs<String>(
            tabs: [FolderTab(value: sel.id, title: sel.target)],
            value: sel.id,
            onChanged: null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${sel.sub} · ${sel.count} ошибок за сутки', style: RescueText.smallSecondary),
                const SizedBox(height: 16),
                const HourBars(
                  title: 'ПО ЧАСАМ',
                  counts: [0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 1, 3, 2, 2, 4],
                  startLabel: 'вчера 21:00',
                  endLabel: 'сейчас',
                  height: 70,
                ),
                const SizedBox(height: 12),
                const RescueTable(
                  minWidth: 420,
                  columns: [RescueColumn('ВРЕМЯ', width: 56), RescueColumn('ЧТО СЛУЧИЛОСЬ'), RescueColumn('АДРЕС')],
                  rows: [
                    RescueTableRow(
                      cells: [
                        Text('20:41', style: TextStyle(color: RescueColors.muted)),
                        Text('соединение сброшено'),
                        Text('213.180.204.211:443', style: TextStyle(color: RescueColors.muted)),
                      ],
                    ),
                    RescueTableRow(
                      cells: [
                        Text('18:10', style: TextStyle(color: RescueColors.muted)),
                        Text('время ожидания истекло'),
                        Text('213.180.204.211:443', style: TextStyle(color: RescueColors.muted)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(onPressed: () {}, child: const Text('Пустить мимо VPN')),
                    OutlinedButton(onPressed: () {}, child: const Text('Всегда через VPN')),
                    TextButton(onPressed: () {}, child: const Text('Скопировать для владельца')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  // ── Подписки и серверы ─────────────────────────────────────────────────────────────────

  List<Widget> _serversScreen() {
    return [
      SectionLabel.screen(
        'Подписки и серверы',
        trailing: OutlinedButton(onPressed: () {}, child: const Text('Проверить пинг')),
      ),
      const SizedBox(height: 20),
      RescueCard.accent(
        semanticLabel: 'Подписка «Основная»',
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 28),
        child: Wrap(
          spacing: 24,
          runSpacing: 20,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RescueBadge(label: 'АКТИВНА', kind: RescueBadgeKind.soft, shape: RescueBadgeShape.tag),
                SizedBox(height: 6),
                Text('Основная', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w300)),
                Text('first.gym-notes.ru', style: TextStyle(fontSize: 13, color: RescueColors.onAccentMuted)),
              ],
            ),
            const Wrap(
              spacing: 22,
              runSpacing: 12,
              children: [
                RingStat.onAccent(value: 0.24, label: '48', title: 'ГБ\nИЗ 200'),
                RingStat.onAccent(value: 0.75, label: '31', title: 'ДЕНЬ\nОСТАЛОСЬ'),
                RingStat.onAccent(value: 0.5, label: '6ч', title: 'ОБНОВЛЕНИЕ\nСАМО'),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(style: RescueTheme.deepFilledButton(), onPressed: () {}, child: const Text('Обновить')),
                OutlinedButton(
                  style: RescueTheme.outlinedOnAccentButton(),
                  onPressed: () {},
                  child: const Text('Переименовать'),
                ),
                OutlinedButton(
                  style: RescueTheme.dangerOnAccentButton(),
                  onPressed: () {},
                  child: const Text('Удалить'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const SectionLabel('Серверы', count: '2'),
      const SizedBox(height: 12),
      RescueGrid(
        minItemWidth: 240,
        spacing: 16,
        children: [
          for (final s in _servers)
            DeepListTile(
              leading: s.code,
              title: s.name,
              subtitle: s.subtitle,
              trailingText: s.ping,
              highlighted: s.value == _server,
              onTap: () => setState(() => _server = s.value),
            ),
          const RescueCard.dashed(
            semanticLabel: 'Запасной',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Запасной', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                Text('Автопереключение появится в следующей версии.', style: RescueText.smallSecondary),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  // ── Настройки ──────────────────────────────────────────────────────────────────────────

  List<Widget> _settings() {
    return [
      const SectionLabel.screen('Настройки'),
      const SizedBox(height: 20),
      RescueGrid(
        minItemWidth: 380,
        spacing: 20,
        children: [
          RescueCard(
            semanticLabel: 'Запуск',
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(padding: EdgeInsets.only(top: 12, bottom: 2), child: SectionLabel('Запуск')),
                for (final (i, e) in _switches.entries.indexed)
                  SettingsSwitchTile(
                    title: e.key,
                    subtitle: _hints[i],
                    value: e.value,
                    divider: i < _switches.length - 1,
                    onChanged: (v) => setState(() => _switches[e.key] = v),
                  ),
              ],
            ),
          ),
          RescueCard(
            semanticLabel: 'Способ работы',
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Способ работы'),
                const SizedBox(height: 12),
                ChoiceCard(
                  title: 'Весь компьютер',
                  description: 'Все программы и игры, работает раздельный туннель',
                  selected: _vpnMode,
                  onTap: () => setState(() => _vpnMode = true),
                ),
                const SizedBox(height: 12),
                ChoiceCard(
                  title: 'Только браузеры',
                  description: 'Режим прокси: без прав администратора',
                  selected: !_vpnMode,
                  onTap: () => setState(() => _vpnMode = false),
                ),
              ],
            ),
          ),
          RescueCard.deep(
            semanticLabel: 'Для опытных',
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: SectionLabel('Для опытных', color: RescueColors.accent),
                ),
                SettingsLinkTile(title: 'Журнал', subtitle: 'Все строки ядра', onDeep: true, onTap: () {}),
                SettingsLinkTile(title: 'DNS', subtitle: 'Какие серверы имён использовать', onDeep: true, onTap: () {}),
                SettingsLinkTile(
                  title: 'Подключение',
                  subtitle: 'Порты, тонкости туннеля',
                  onDeep: true,
                  divider: false,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  // ── Остальные кирпичики и Material-виджеты в теме ─────────────────────────────────────

  List<Widget> _misc() {
    const scores = [
      ScoreRow(
        name: 'Общая оценка',
        value: '92',
        trend: 3,
        good: 80,
        fair: 14,
        poor: 6,
        caption: 'всё в порядке',
        emphasized: true,
      ),
      ScoreRow(name: 'Стабильность', value: '81', trend: -4, good: 62, fair: 24, poor: 14, caption: 'разброс 6 мс'),
      ScoreRow(name: 'Нет данных', value: '—', good: 0, fair: 0, poor: 0, caption: 'замеры идут, пока VPN включён'),
    ];
    return [
      const SectionLabel.screen('Прочие кирпичики'),
      const SizedBox(height: 20),
      RescueGrid(
        minItemWidth: 380,
        spacing: 20,
        children: [
          const RescueCard(
            semanticLabel: 'Здоровье подключения',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title: 'Здоровье подключения', trailingText: 'за 24 часа'),
                SizedBox(height: 14),
                RescueGrid(minItemWidth: 160, spacing: 24, runSpacing: 16, children: scores),
              ],
            ),
          ),
          const RescueCard(
            semanticLabel: 'Оценка по дням',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title: 'Оценка по дням', trailingText: 'последние 30 дней'),
                SizedBox(height: 10),
                LineChart(
                  values: [91.6, 92.8, 92, 93.2, 76, 89.6, 92.4, 91.2, 80, 92, 94],
                  minY: 70,
                  yTicks: [100, 90, 80, 70],
                  xLabels: ['10 сен', '25 сен', '9 окт'],
                  height: 200,
                  markers: [
                    LineChartMarker(index: 4, color: RescueColors.warn, label: 'сервер был недоступен 40 мин'),
                    LineChartMarker(index: 8, color: RescueColors.muted),
                  ],
                  semanticLabel: 'График оценки: держится около 90, провалы до 76 и до 80',
                ),
                SizedBox(height: 10),
                ChartLegend(
                  items: [
                    ChartLegendItem(color: RescueColors.accent, label: 'Общая оценка', line: true),
                    ChartLegendItem(color: RescueColors.warn, label: 'Серьёзный сбой'),
                    ChartLegendItem(color: RescueColors.muted, label: 'Были ошибки'),
                  ],
                ),
              ],
            ),
          ),
          RescueCard(
            semanticLabel: 'Правила',
            child: Wrap(
              spacing: 20,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const DonutChart(
                  centerValue: '71',
                  centerLabel: 'правило',
                  segments: [
                    DonutSegment(value: 12, color: RescueColors.accent, label: 'через VPN'),
                    DonutSegment(value: 38, color: RescueColors.text, label: 'мимо VPN'),
                    DonutSegment(value: 21, color: RescueColors.muted, label: 'по общим правилам'),
                  ],
                ),
                SizedBox(
                  width: 200,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(title: 'Правила', actionLabel: 'Открыть', onAction: () => setState(() => _nav = 1)),
                      const StatTile(label: 'Израсходовано', value: '48 из 200 ГБ', progress: 0.24, inset: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
          RescueCard(
            semanticLabel: 'Метки и переключатели',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Метки', count: '6'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in RescueBadgeKind.values) RescueBadge(label: k.name, kind: k),
                    const RescueBadge.tag(label: 'VPN', kind: RescueBadgeKind.soft),
                    const FrameTag('ВКЛ'),
                  ],
                ),
                const SizedBox(height: 16),
                // Карточка статуса для низа меню (в широком окне она же — в RescueShell.footer).
                SizedBox(
                  width: 232,
                  child: ShellStatusCard(
                    state: _power,
                    title: _on ? 'Подключено' : 'Отключено',
                    subtitle: _on ? 'Нидерланды · 48 мс' : 'нажмите кнопку',
                    onPower: _togglePower,
                  ),
                ),
                const SizedBox(height: 16),
                ConnectionPill(
                  connected: _connected,
                  label: _connected ? 'Подключено · Нидерланды · 48 мс' : 'Отключено',
                  onChanged: (v) => setState(() => _connected = v),
                ),
                const SizedBox(height: 16),
                PillSegmented<String>(
                  semanticLabel: 'Пример таблеток',
                  segments: const [
                    PillSegment(value: 'auto', label: 'АВТО'),
                    PillSegment(value: 'by', label: 'МИМО'),
                    PillSegment(value: 'vpn', label: 'VPN'),
                  ],
                  value: _pill,
                  onChanged: (v) => setState(() => _pill = v),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    RescueToggle(
                      value: _connected,
                      onChanged: (v) => setState(() => _connected = v),
                      semanticLabel: 'Пример',
                    ),
                    Switch(value: _connected, onChanged: (v) => setState(() => _connected = v)),
                    Checkbox(value: _checkbox, onChanged: (v) => setState(() => _checkbox = v ?? false)),
                    SizedBox(
                      width: 180,
                      child: Slider(value: _slider, onChanged: (v) => setState(() => _slider = v)),
                    ),
                    // Кадр «подключения» без анимации — чтобы витрина не крутилась бесконечно в тестах.
                    TickerMode(
                      enabled: false,
                      child: PowerButton(state: PowerState.connecting, onPressed: () {}, size: 96),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ];
  }
}
