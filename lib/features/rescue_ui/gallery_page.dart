import 'package:flutter/material.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';

/// Шлюпка: витрина всех кирпичиков на тестовых данных (только для отладки, маршрут /ui-gallery).
class RescueGalleryPage extends StatefulWidget {
  const RescueGalleryPage({super.key});

  @override
  State<RescueGalleryPage> createState() => _RescueGalleryPageState();
}

enum _Period { hour, day, week }

enum _Kind { all, app, site, ip }

class _App {
  const _App(this.name, this.detail, this.letter, this.tint, this.kind, this.live, this.errors);

  final String name;
  final String detail;
  final String letter;
  final Color tint;
  final String kind;
  final String live;
  final int errors;
}

class _RescueGalleryPageState extends State<RescueGalleryPage> {
  int _nav = 0;
  bool _connected = true;
  _Period _period = _Period.day;
  _Kind _filter = _Kind.all;
  bool _vpnMode = true;
  int _server = 0;
  final _switches = <String, bool>{
    'Запускать при входе в Windows': true,
    'Подключаться сразу': true,
    'Уведомление Windows при обрыве связи': false,
  };
  static const _hints = [
    'Без окна «Разрешить изменения?»',
    'Если VPN был включён при выходе',
    'Если сервер не отвечает больше минуты',
  ];
  final _routes = <String, RouteChoice>{
    'Google Chrome': RouteChoice.auto,
    'Telegram': RouteChoice.vpn,
    'Steam': RouteChoice.bypass,
    'kinopoisk.ru': RouteChoice.bypass,
  };

  static const _apps = [
    _App('Google Chrome', 'chrome.exe', 'G', Color(0xFF2F6FD6), 'Программа', '14 соединений', 0),
    _App('Telegram', 'Telegram.exe', 'T', Color(0xFF1F8BC4), 'Программа', '3 соединения', 0),
    _App('Steam', 'steam.exe · из списка игр', 'S', Color(0xFF1B2838), 'Программа', 'не в сети', 1),
    _App('kinopoisk.ru', 'и все поддомены', 'K', Color(0xFFE0661B), 'Сайт', 'не в сети', 5),
  ];

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: RescueTheme.dark(),
      child: RescueShell(
        selectedIndex: _nav,
        onSelected: (i) => setState(() => _nav = i),
        items: const [
          RescueNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Обзор'),
          RescueNavItem(icon: Icons.call_split_rounded, label: 'Раздельный туннель'),
          RescueNavItem(icon: Icons.warning_amber_rounded, label: 'Ошибки соединений', badge: true),
          RescueNavItem(icon: Icons.dns_outlined, label: 'Подписки и серверы'),
        ],
        bottomItem: const RescueNavItem(icon: Icons.tune_rounded, label: 'Настройки'),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: 16),
              RescueGrid(minItemWidth: 420, spacing: 16, children: [_health(), _chart()]),
              const SizedBox(height: 16),
              _errors(),
              const SizedBox(height: 16),
              RescueGrid(minItemWidth: 420, spacing: 16, children: [_rules(), _subscription()]),
              const SizedBox(height: 16),
              _tunnel(),
              const SizedBox(height: 16),
              _problems(),
              const SizedBox(height: 16),
              _servers(),
              const SizedBox(height: 16),
              _settings(),
              const SizedBox(height: 16),
              _badges(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Витрина кирпичиков', style: RescueText.pageTitle),
        ConnectionPill(
          connected: _connected,
          label: _connected ? 'Подключено · Нидерланды · 48 мс' : 'Отключено',
          onChanged: (v) => setState(() => _connected = v),
        ),
      ],
    );
  }

  Widget _health() {
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
      ScoreRow(
        name: 'Пинг до сервера',
        value: '95',
        trend: 0,
        good: 88,
        fair: 9,
        poor: 3,
        caption: '48 мс, обычно 45–60',
      ),
      ScoreRow(
        name: 'Стабильность',
        value: '81',
        trend: -4,
        good: 62,
        fair: 24,
        poor: 14,
        caption: '2 переподключения за сутки',
      ),
      ScoreRow(
        name: 'Соединения без ошибок',
        value: '97',
        trend: 1,
        good: 92,
        fair: 6,
        poor: 2,
        caption: '3% соединений с ошибкой',
      ),
      ScoreRow(name: 'DNS', value: '100', trend: 0, good: 100, fair: 0, poor: 0, caption: 'все адреса находятся'),
      ScoreRow(name: 'Нет данных', value: '—', good: 0, fair: 0, poor: 0, caption: 'замеры идут, пока VPN включён'),
    ];
    return const RescueCard(
      semanticLabel: 'Здоровье подключения',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: 'Здоровье подключения', trailingText: 'за 24 часа'),
          SizedBox(height: 14),
          RescueGrid(minItemWidth: 160, spacing: 24, runSpacing: 16, children: scores),
        ],
      ),
    );
  }

  Widget _chart() {
    return const RescueCard(
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
            markers: [
              LineChartMarker(index: 4, color: RescueColors.poor, label: 'сервер был недоступен 40 мин'),
              LineChartMarker(index: 8, color: RescueColors.fair),
            ],
            semanticLabel: 'График оценки: держится около 90, провалы до 76 и до 80',
          ),
          SizedBox(height: 10),
          ChartLegend(
            items: [
              ChartLegendItem(color: RescueColors.accent, label: 'Общая оценка', line: true),
              ChartLegendItem(color: RescueColors.poor, label: 'Серьёзный сбой'),
              ChartLegendItem(color: RescueColors.fair, label: 'Были ошибки'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errors() {
    const via = RescueBadge.tag(label: 'VPN', kind: RescueBadgeKind.soft, semanticLabel: 'через VPN');
    const by = RescueBadge.tag(label: 'мимо', kind: RescueBadgeKind.bypass, semanticLabel: 'мимо VPN');
    const rows = [
      ('20:41', 'Google Chrome', 'kinopoisk.ru', 'соединение сброшено сайтом', via),
      ('20:31', 'Discord', 'gateway.discord.gg', 'обрыв через 2 мин', via),
      ('20:12', 'Steam', 'cdn.steamstatic.com', 'время ожидания истекло', by),
      ('19:58', 'Яндекс Браузер', 'api.example-shop.ru', 'адрес не найден (DNS)', by),
    ];
    return RescueCard(
      semanticLabel: 'Ошибки соединений',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Ошибки соединений',
            badges: const [
              RescueBadge(label: '7 за час', kind: RescueBadgeKind.important),
              RescueBadge(label: '23 за сутки'),
            ],
            actionLabel: 'Все ошибки',
            onAction: () => setState(() => _nav = 2),
          ),
          const SizedBox(height: 12),
          RescueTable(
            columns: const [
              RescueColumn('Время', width: 60),
              RescueColumn('Программа', flex: 1.1),
              RescueColumn('Сайт или адрес', flex: 1.4),
              RescueColumn('Что случилось', flex: 1.6),
              RescueColumn('Путь', width: 80, alignEnd: true),
            ],
            rows: [
              for (final (time, app, target, what, route) in rows)
                RescueTableRow(
                  cells: [
                    Text(time, style: const TextStyle(color: RescueColors.textSecondary)),
                    Text(app),
                    Text(target, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(what, style: const TextStyle(color: RescueColors.textTertiary)),
                    route,
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rules() {
    Widget group(String name, int count, Color color) => Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: RescueColors.background, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: RescueText.body)),
          Text('$count', style: RescueText.bodyStrong),
        ],
      ),
    );
    return RescueCard(
      semanticLabel: 'Правила',
      child: Wrap(
        spacing: 20,
        runSpacing: 20,
        alignment: WrapAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title: 'Правила', actionLabel: 'Открыть', onAction: () => setState(() => _nav = 1)),
                const SizedBox(height: 6),
                group('Через VPN', 12, RescueColors.accent),
                const SizedBox(height: 4),
                group('Мимо VPN', 38, RescueColors.teal),
                const SizedBox(height: 4),
                group('По общим правилам', 21, RescueColors.fair),
              ],
            ),
          ),
          const DonutChart(
            centerValue: '71',
            centerLabel: 'правило',
            segments: [
              DonutSegment(value: 12, color: RescueColors.accent, label: 'через VPN'),
              DonutSegment(value: 38, color: RescueColors.teal, label: 'мимо VPN'),
              DonutSegment(value: 21, color: RescueColors.fair, label: 'по общим правилам'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _subscription() {
    return RescueCard(
      semanticLabel: 'Подписка',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: 'Подписка', actionLabel: 'Серверы', onAction: () => setState(() => _nav = 3)),
          const Text('Основной · first.gym-notes.ru', style: RescueText.smallSecondary),
          const SizedBox(height: 10),
          const Text.rich(
            TextSpan(
              text: '48 ГБ ',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              children: [
                TextSpan(
                  text: 'из 200 за месяц',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: RescueColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const RescueProgressBar(value: 0.24, height: 8),
          const SizedBox(height: 10),
          const Text('Действует до 9 ноября · обновлена в 12:40', style: RescueText.smallSecondary),
        ],
      ),
    );
  }

  Widget _tunnel() {
    final apps = _apps.where(
      (a) => switch (_filter) {
        _Kind.all => true,
        _Kind.app => a.kind == 'Программа',
        _Kind.site => a.kind == 'Сайт',
        _Kind.ip => a.kind == 'IP / сеть',
      },
    );
    int count(RouteChoice r) => _routes.values.where((v) => v == r).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RescueGrid(
          children: [
            StatTile(label: 'Через VPN', value: '${count(RouteChoice.vpn)}', markerColor: RescueColors.accent),
            StatTile(label: 'Мимо VPN', value: '${count(RouteChoice.bypass)}', markerColor: RescueColors.teal),
            StatTile(label: 'По общим правилам', value: '${count(RouteChoice.auto)}', markerColor: RescueColors.fair),
            const StatTile(label: 'Сейчас в сети', value: '2', markerColor: RescueColors.good),
          ],
        ),
        const SizedBox(height: 16),
        RescueCard(
          semanticLabel: 'Правила раздельного туннеля',
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilterChips<_Kind>(
                options: const [(_Kind.all, 'Всё'), (_Kind.app, 'Программы'), (_Kind.site, 'Сайты'), (_Kind.ip, 'IP')],
                selected: _filter,
                onSelected: (k) => setState(() => _filter = k),
              ),
              const SizedBox(height: 12),
              RescueTable(
                minWidth: 820,
                rowHeight: 60,
                columns: const [
                  RescueColumn('Название', flex: 2.4),
                  RescueColumn('Тип'),
                  RescueColumn('Куда идёт', width: 230),
                  RescueColumn('Сейчас', flex: 1.4),
                  RescueColumn('Ошибки за сутки', alignEnd: true),
                ],
                rows: [for (final a in apps) _tunnelRow(a)],
              ),
              const SizedBox(height: 12),
              const Text(
                '«Авто» — решают общие правила: российские сайты напрямую, остальное через VPN.',
                style: RescueText.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }

  RescueTableRow _tunnelRow(_App a) {
    final online = a.live != 'не в сети';
    return RescueTableRow(
      cells: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: a.tint, borderRadius: BorderRadius.circular(10)),
              child: ExcludeSemantics(
                child: Text(
                  a.letter,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(a.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(a.detail, style: RescueText.caption),
                ],
              ),
            ),
          ],
        ),
        Text(a.kind, style: const TextStyle(color: RescueColors.textTertiary)),
        RouteSwitch(
          value: _routes[a.name] ?? RouteChoice.auto,
          semanticLabel: 'Куда идёт ${a.name}',
          onChanged: (r) => setState(() => _routes[a.name] = r),
        ),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: online ? RescueColors.good : RescueColors.muted, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(a.live, style: TextStyle(color: online ? RescueColors.text : RescueColors.textSecondary)),
            ),
          ],
        ),
        if (a.errors == 0)
          const Text('нет', style: TextStyle(color: RescueColors.textSecondary))
        else
          RescueBadge.tag(
            label: '${a.errors}',
            kind: a.errors > 3 ? RescueBadgeKind.important : RescueBadgeKind.warning,
          ),
      ],
    );
  }

  Widget _problems() {
    return RescueCard(
      semanticLabel: 'Ошибки по часам',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('kinopoisk.ru', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              PeriodSwitch<_Period>(
                options: const [(_Period.hour, 'Час'), (_Period.day, 'Сутки'), (_Period.week, 'Неделя')],
                value: _period,
                onChanged: (p) => setState(() => _period = p),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Google Chrome · идёт через VPN · 5 ошибок за сутки', style: RescueText.smallSecondary),
          const SizedBox(height: 14),
          const HourBars(
            title: 'Ошибки по часам',
            counts: [0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 1, 3, 2, 2, 4],
            startLabel: 'вчера 21:00',
            endLabel: 'сейчас',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: () {}, child: const Text('Пустить мимо VPN')),
              OutlinedButton(onPressed: () {}, child: const Text('Всегда через VPN')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _servers() {
    const servers = [
      ('Автовыбор', 'сам берёт самый быстрый из рабочих', '—'),
      ('Нидерланды · first.gym-notes.ru', 'основной', 'VLESS Reality'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton(onPressed: () {}, child: const Text('Проверить все')),
            FilledButton(onPressed: () {}, child: const Text('+ Добавить подписку')),
          ],
        ),
        const SizedBox(height: 16),
        RescueGrid(
          minItemWidth: 300,
          spacing: 16,
          children: [
            RescueCard(
              semanticLabel: 'Подписка «Основной»',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(
                    title: 'Основной',
                    titleStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    badges: [RescueBadge(label: 'активна', kind: RescueBadgeKind.success)],
                  ),
                  const SizedBox(height: 14),
                  const RescueGrid(
                    minItemWidth: 160,
                    children: [
                      StatTile(label: 'Израсходовано', value: '48 из 200 ГБ', progress: 0.24, inset: true),
                      StatTile(label: 'Действует до', value: '9 ноября', caption: 'ещё 31 день', inset: true),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(onPressed: () {}, child: const Text('Обновить сейчас')),
                      OutlinedButton(
                        onPressed: () {},
                        style: RescueTheme.dangerOutlinedButton(),
                        child: const Text('Удалить'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            RescueCard.dashed(
              semanticLabel: 'Запасной вариант',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Запасной', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  const Text(
                    'Если основной сервер не отвечает 30 секунд, программа сама переключится на запасной.',
                    style: TextStyle(fontSize: 14, height: 1.5, color: RescueColors.textTertiary),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: () {}, child: const Text('Добавить запасной')),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        RescueCard(
          semanticLabel: 'Серверы',
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'Серверы в подписке', trailingText: 'Нажмите строку, чтобы выбрать'),
              const SizedBox(height: 8),
              RescueTable(
                rowHeight: 64,
                gap: 14,
                columns: const [
                  RescueColumn('', width: 28),
                  RescueColumn('Сервер', flex: 2),
                  RescueColumn('Протокол'),
                  RescueColumn('Пинг', flex: 1.6),
                  RescueColumn('Здоровье за сутки', flex: 1.4),
                ],
                rows: [
                  for (final (i, (name, sub, proto)) in servers.indexed)
                    RescueTableRow(
                      selected: i == _server,
                      onTap: () => setState(() => _server = i),
                      semanticLabel: '$name, $proto, пинг 48 мс, здоровье 92',
                      cells: [
                        _radio(i == _server),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            Text(sub, style: RescueText.caption),
                          ],
                        ),
                        Text(proto, style: const TextStyle(color: RescueColors.textTertiary)),
                        const Row(
                          children: [
                            Expanded(child: RescueProgressBar(value: 0.16)),
                            SizedBox(width: 10),
                            SizedBox(width: 56, child: Text('48 мс', style: RescueText.bodyStrong)),
                          ],
                        ),
                        const Row(
                          children: [
                            Expanded(child: ScoreBar(good: 80, fair: 14, poor: 6, gap: 2)),
                            SizedBox(width: 8),
                            SizedBox(width: 28, child: Text('92', style: RescueText.bodyStrong)),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _radio(bool selected) => Container(
    width: 18,
    height: 18,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: selected ? RescueColors.accent : RescueColors.muted, width: 2),
    ),
    child: selected
        ? Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: RescueColors.accent, shape: BoxShape.circle),
          )
        : null,
  );

  Widget _settings() {
    return RescueGrid(
      minItemWidth: 420,
      spacing: 16,
      children: [
        RescueCard(
          semanticLabel: 'Запуск',
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 4),
                child: Text('Запуск', style: RescueText.cardTitle),
              ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Способ работы', style: RescueText.cardTitle),
              const SizedBox(height: 12),
              ChoiceCard(
                title: 'Весь компьютер (VPN)',
                description: 'Все программы и игры. Работают раздельный туннель и список ошибок.',
                selected: _vpnMode,
                onTap: () => setState(() => _vpnMode = true),
              ),
              const SizedBox(height: 12),
              ChoiceCard(
                title: 'Только браузеры (прокси)',
                description: 'Без прав администратора. Остальные программы идут напрямую.',
                selected: !_vpnMode,
                onTap: () => setState(() => _vpnMode = false),
              ),
            ],
          ),
        ),
        RescueCard(
          semanticLabel: 'Для опытных',
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text('Для опытных', style: RescueText.cardTitle),
              ),
              SettingsLinkTile(title: 'DNS', subtitle: 'Яндекс для прямых, через VPN для остальных', onTap: () {}),
              SettingsLinkTile(title: 'Журнал ядра', subtitle: 'Все строки, для поиска проблем', onTap: () {}),
            ],
          ),
        ),
      ],
    );
  }

  Widget _badges() {
    return const RescueCard(
      semanticLabel: 'Бейджи',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: 'Бейджи'),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              RescueBadge(label: 'важно', kind: RescueBadgeKind.important),
              RescueBadge(label: 'внимание', kind: RescueBadgeKind.warning),
              RescueBadge(label: 'мягкий акцент', kind: RescueBadgeKind.soft),
              RescueBadge(label: 'нейтральный'),
              RescueBadge(label: 'мимо', kind: RescueBadgeKind.bypass),
              RescueBadge(label: 'активна', kind: RescueBadgeKind.success),
              RescueBadge.tag(label: 'VPN', kind: RescueBadgeKind.soft),
              RescueBadge.tag(label: 'мимо', kind: RescueBadgeKind.bypass),
            ],
          ),
        ],
      ),
    );
  }
}
