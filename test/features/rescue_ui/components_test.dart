import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';

import 'helpers.dart';

void main() {
  testWidgets('тёмная тема, карточки и метки сохраняют читаемые подписи', (tester) async {
    final theme = RescueTheme.dark();
    expect(theme.brightness, Brightness.dark);
    expect(theme.textTheme.bodyMedium!.fontFamily, 'Segoe UI');
    await pumpRescue(
      tester,
      const Column(
        children: [
          RescueCard(semanticLabel: 'Секция', child: Text('карточка')),
          RescueCard.inset(child: Text('вложенная')),
          RescueCard.dashed(child: Text('пусто')),
          StatTile(label: 'Через VPN', value: '12'),
          StatTile(label: 'Израсходовано', value: '48 из 200 ГБ', progress: 0.24, inset: true),
          RescueBadge(label: 'Предупреждение', kind: RescueBadgeKind.warning),
        ],
      ),
    );
    for (final text in ['карточка', 'вложенная', 'пусто', '12', '48 из 200 ГБ', 'Предупреждение']) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.bySemanticsLabel('Секция'), findsOneWidget);
    expect(find.bySemanticsLabel('Через VPN, 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('SectionHeader: заголовок, подпись, ссылка вызывает колбэк', (tester) async {
    var taps = 0;
    await pumpRescue(
      tester,
      SectionHeader(
        title: 'Ошибки соединений',
        badges: const [RescueBadge(label: '7 за час', kind: RescueBadgeKind.important)],
        actionLabel: 'Все ошибки',
        onAction: () => taps++,
      ),
    );
    expect(find.text('Ошибки соединений'), findsOneWidget);
    expect(find.text('7 за час'), findsOneWidget);
    await tester.tap(find.text('Все ошибки ›'));
    expect(taps, 1);
    expect(tester.getSize(find.byType(RescueLink)).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('Все ошибки'), findsOneWidget);
  });

  testWidgets('ConnectionPill: нажатие переключает, есть подпись для чтеца', (tester) async {
    bool? next;
    await pumpRescue(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: ConnectionPill(connected: true, label: 'Подключено', onChanged: (v) => next = v),
      ),
    );
    await tester.tap(find.text('Подключено'));
    expect(next, isFalse);
    expect(tester.getSize(find.byType(ConnectionPill)).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(find.byType(ConnectionPill)),
      matchesSemantics(
        label: 'Подключено',
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
  });

  testWidgets('RescueTable: заголовки, строки, прокрутка на узком окне', (tester) async {
    Widget table() => const RescueTable(
      minWidth: 600,
      columns: [
        RescueColumn('Время', width: 60),
        RescueColumn('Программа', flex: 1.1),
        RescueColumn('Путь', width: 80, alignEnd: true),
      ],
      rows: [
        RescueTableRow(cells: [Text('20:41'), Text('Google Chrome'), Text('VPN')]),
        RescueTableRow(cells: [Text('20:12'), Text('Steam'), Text('мимо')]),
      ],
    );
    await pumpRescue(tester, table());
    expect(find.text('Программа'), findsOneWidget);
    expect(find.text('Steam'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget); // только внешний

    await pumpRescue(tester, table(), size: const Size(400, 800));
    final horizontal = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    expect(horizontal, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RescueTable: строка-кнопка не ниже 44 и выбирается', (tester) async {
    var tapped = -1;
    await pumpRescue(
      tester,
      RescueTable(
        minWidth: 300,
        rowHeight: 30,
        columns: const [RescueColumn('Сервер')],
        rows: [
          for (var i = 0; i < 2; i++)
            RescueTableRow(cells: [Text('Сервер $i')], onTap: () => tapped = i, semanticLabel: 'Сервер $i'),
        ],
      ),
    );
    await tester.tap(find.text('Сервер 1'));
    expect(tapped, 1);
    expect(tester.getSize(find.byType(InkWell).last).height, greaterThanOrEqualTo(44));
  });

  testWidgets('DonutChart: число в центре, подпись для чтеца, пустые данные', (tester) async {
    await pumpRescue(
      tester,
      const Column(
        children: [
          DonutChart(
            centerValue: '71',
            centerLabel: 'правило',
            segments: [
              DonutSegment(value: 12, color: RescueColors.accent, label: 'через VPN'),
              DonutSegment(value: 38, color: RescueColors.teal, label: 'мимо VPN'),
            ],
          ),
          DonutChart(
            segments: [DonutSegment(value: 0, color: RescueColors.accent)],
            semanticLabel: 'пусто',
          ),
        ],
      ),
    );
    expect(find.text('71'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('через VPN: 12')), findsOneWidget);
    expect(find.bySemanticsLabel('пусто'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LineChart: рисуется, рвётся на null, отметки вне диапазона не ломают', (tester) async {
    await pumpRescue(
      tester,
      const LineChart(
        values: [90, 92, null, 76, 94],
        minY: 70,
        yTicks: [100, 90, 80, 70],
        xLabels: ['10 сен', '25 сен', '9 окт'],
        markers: [
          LineChartMarker(index: 3, color: RescueColors.poor, label: 'сервер был недоступен 40 мин'),
          LineChartMarker(index: 2, color: RescueColors.fair),
          LineChartMarker(index: 99, color: RescueColors.fair),
        ],
        semanticLabel: 'График оценки',
      ),
    );
    expect(find.bySemanticsLabel('График оценки'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);

    await pumpRescue(tester, const LineChart(values: [], semanticLabel: 'пусто'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('HourBars: ноль — чёрточка 2 px, максимум — во всю высоту, цвета по порогу', (tester) async {
    await pumpRescue(
      tester,
      const HourBars(counts: [0, 1, 4], title: 'Ошибки по часам', startLabel: 'вчера', endLabel: 'сейчас'),
    );
    double h(int i) => tester.getSize(find.byKey(ValueKey('hour-bar-$i'))).height;
    Color c(int i) =>
        (tester.widget<Container>(find.byKey(ValueKey('hour-bar-$i'))).decoration! as BoxDecoration).color!;
    expect(h(0), 2);
    expect(h(2), 63);
    expect(h(1), greaterThan(10));
    expect(h(1), lessThan(h(2)));
    // Стиль «Д»: обычный столбик жёлтый, от порога — оранжевый.
    expect(c(0), RescueColors.line);
    expect(c(1), RescueColors.accent);
    expect(c(2), RescueColors.warn);
    expect(find.text('сейчас'), findsOneWidget);
  });

  testWidgets('FilterChips: выбор и подписи', (tester) async {
    var selected = 'all';
    await pumpRescue(
      tester,
      StatefulBuilder(
        builder: (context, setState) => FilterChips<String>(
          options: const [('all', 'Всё'), ('app', 'Программы')],
          selected: selected,
          onSelected: (v) => setState(() => selected = v),
        ),
      ),
    );
    await tester.tap(find.text('Программы'));
    await tester.pump();
    expect(selected, 'app');
    expect(tester.getSemantics(find.text('Программы')), containsSemantics(isSelected: true));
    expect(
      tester.getSize(find.ancestor(of: find.text('Всё'), matching: find.byType(InkWell))).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('PeriodSwitch: клик и стрелки', (tester) async {
    var period = 'day';
    await pumpRescue(
      tester,
      StatefulBuilder(
        builder: (context, setState) => PeriodSwitch<String>(
          options: const [('hour', 'Час'), ('day', 'Сутки'), ('week', 'Неделя')],
          value: period,
          onChanged: (v) => setState(() => period = v),
        ),
      ),
    );
    await tester.tap(find.text('Час'));
    await tester.pump();
    expect(period, 'hour');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(period, 'week', reason: 'стрелка влево с первого — по кругу на последний');
    expect(tester.getSize(find.byType(RescueSegmented<String>)).height, greaterThanOrEqualTo(44));
  });

  testWidgets('SettingsSwitchTile: нажатие строки переключает, Semantics как у переключателя', (tester) async {
    var value = false;
    await pumpRescue(
      tester,
      StatefulBuilder(
        builder: (context, setState) => SettingsSwitchTile(
          title: 'Подключаться сразу',
          subtitle: 'Если VPN был включён при выходе',
          value: value,
          onChanged: (v) => setState(() => value = v),
        ),
      ),
    );
    await tester.tap(find.text('Подключаться сразу'));
    await tester.pump();
    expect(value, isTrue);
    final semantics = tester.getSemantics(find.byType(SettingsSwitchTile));
    expect(semantics.label, 'Подключаться сразу');
    expect(semantics.hint, 'Если VPN был включён при выходе');
    expect(semantics, containsSemantics(isToggled: true));
    expect(tester.getSize(find.byType(SettingsSwitchTile)).height, greaterThanOrEqualTo(64));
  });

  testWidgets('ChoiceCard и SettingsLinkTile', (tester) async {
    var choice = 0;
    var opened = false;
    await pumpRescue(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Column(
          children: [
            ChoiceCard(title: 'Весь компьютер (VPN)', selected: choice == 0, onTap: () => setState(() => choice = 0)),
            ChoiceCard(
              title: 'Только браузеры (прокси)',
              description: 'Без прав администратора.',
              selected: choice == 1,
              onTap: () => setState(() => choice = 1),
            ),
            SettingsLinkTile(title: 'DNS', subtitle: 'Яндекс', onTap: () => opened = true),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Только браузеры (прокси)'));
    await tester.pump();
    expect(choice, 1);
    expect(tester.getSemantics(find.byType(ChoiceCard).last), containsSemantics(isChecked: true));
    await tester.tap(find.text('DNS'));
    expect(opened, isTrue);
  });

  testWidgets('RescueToggle сам по себе: зона 44 и подпись', (tester) async {
    var v = false;
    await pumpRescue(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: RescueToggle(value: v, onChanged: (x) => v = x, semanticLabel: 'Сбор ошибок'),
      ),
    );
    await tester.tap(find.byType(RescueToggle));
    expect(v, isTrue);
    expect(tester.getSize(find.byType(RescueToggle)).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('Сбор ошибок'), findsOneWidget);
  });

  testWidgets('RescueGrid: колонки по ширине', (tester) async {
    await pumpRescue(
      tester,
      const RescueGrid(
        children: [
          SizedBox(key: ValueKey('a'), height: 10),
          SizedBox(height: 10),
          SizedBox(height: 10),
        ],
      ),
      size: const Size(500, 400),
    );
    // 500 − 32 отступа = 468: влезает 2 колонки по 228.
    expect(tester.getSize(find.byKey(const ValueKey('a'))).width, 228);
  });

  testWidgets('RescueGrid masonry: колонка складывается сама, без дыр под короткой карточкой', (tester) async {
    await pumpRescue(
      tester,
      const RescueGrid(
        masonry: true,
        children: [
          SizedBox(key: ValueKey('a'), height: 40),
          SizedBox(key: ValueKey('b'), height: 200),
          SizedBox(key: ValueKey('c'), height: 30),
          SizedBox(key: ValueKey('d'), height: 30),
        ],
      ),
      size: const Size(500, 400),
    );
    Rect r(String k) => tester.getRect(find.byKey(ValueKey(k)));
    expect(r('a').width, 228);
    // «c» — во второй строке первой колонки: сразу под «a», а не под высокой «b».
    expect(r('c').left, r('a').left);
    expect(r('c').top, r('a').bottom + 12);
    expect(r('d').left, r('b').left);
    expect(r('d').top, r('b').bottom + 12);
  });
}
