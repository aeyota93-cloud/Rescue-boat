import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';

import 'helpers.dart';

void main() {
  group('FolderTabs', () {
    Future<List<String>> pumpTabs(WidgetTester tester, {String initial = 'now'}) async {
      final calls = <String>[];
      var value = initial;
      await pumpRescue(
        tester,
        StatefulBuilder(
          builder: (context, setState) => FolderTabs<String>(
            semanticLabel: 'Сводка',
            tabs: const [
              FolderTab(value: 'now', title: 'Связь', badge: 'ВКЛ'),
              FolderTab(value: 'health', title: 'Здоровье', badge: '92'),
              FolderTab(value: 'more', title: 'Ещё'),
            ],
            value: value,
            onChanged: (v) => setState(() {
              calls.add(v);
              value = v;
            }),
            child: Text('Содержимое $value'),
          ),
        ),
      );
      return calls;
    }

    BorderRadius cardRadius(WidgetTester tester) =>
        (tester.widget<Container>(find.byKey(const ValueKey('folder-tabs-card'))).decoration! as BoxDecoration)
                .borderRadius!
            as BorderRadius;

    testWidgets('заголовки и метки, активная сливается с карточкой', (tester) async {
      await pumpTabs(tester);
      expect(find.text('Связь'), findsOneWidget);
      expect(find.text('ВКЛ'), findsOneWidget);
      expect(find.text('92'), findsOneWidget);
      expect(find.byType(FrameTag), findsNWidgets(2));
      expect(tester.widget<Text>(find.text('Связь')).style!.fontSize, 24);
      expect(tester.widget<Text>(find.text('Связь')).style!.fontWeight, FontWeight.w300);
      // Активна первая — у карточки нет верхнего левого скругления; закладка того же цвета.
      expect(cardRadius(tester).topLeft, Radius.zero);
      expect(cardRadius(tester).topRight, const Radius.circular(28));
      final active = tester.widget<AnimatedContainer>(
        find.ancestor(of: find.text('Связь'), matching: find.byType(AnimatedContainer)),
      );
      expect((active.decoration! as BoxDecoration).color, RescueColors.card);
      // Низ активной закладки = верх карточки.
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('folder-tab-0'))).dy,
        tester.getTopLeft(find.byKey(const ValueKey('folder-tabs-card'))).dy,
      );
      expect(tester.getSize(find.byKey(const ValueKey('folder-tab-0'))).height, greaterThanOrEqualTo(52));
    });

    testWidgets('клик переключает; вторая активна — карточка скруглена целиком', (tester) async {
      final calls = await pumpTabs(tester);
      await tester.tap(find.text('Здоровье'));
      await tester.pump();
      expect(calls, ['health']);
      expect(find.text('Содержимое health'), findsOneWidget);
      expect(cardRadius(tester).topLeft, const Radius.circular(28));
      final inactive = tester.widget<AnimatedContainer>(
        find.ancestor(of: find.text('Связь'), matching: find.byType(AnimatedContainer)),
      );
      expect((inactive.decoration! as BoxDecoration).color, Colors.transparent);
    });

    testWidgets('клавиатура: Tab, стрелки по кругу, Home/End', (tester) async {
      final calls = await pumpTabs(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(calls.last, 'health');
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(calls.last, 'more');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(calls.last, 'now');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(calls.last, 'more');
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(calls, ['health', 'more', 'now', 'more', 'now']);
    });

    testWidgets('Semantics: кнопки-закладки с отметкой выбора', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTabs(tester);
      expect(find.bySemanticsLabel('Сводка'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Связь, ВКЛ')),
        containsSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );
      expect(tester.getSemantics(find.bySemanticsLabel('Здоровье, 92')), containsSemantics(isSelected: false));
      handle.dispose();
    });
  });

  group('PillSegmented', () {
    testWidgets('клик, клавиатура и цвета вариантов', (tester) async {
      var value = 'auto';
      await pumpRescue(
        tester,
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              PillSegmented<String>(
                semanticLabel: 'Куда идёт Chrome',
                segments: const [
                  PillSegment(value: 'auto', label: 'АВТО'),
                  PillSegment(value: 'by', label: 'МИМО', semanticLabel: 'Мимо VPN'),
                  PillSegment(value: 'vpn', label: 'VPN'),
                ],
                value: value,
                onChanged: (v) => setState(() => value = v),
              ),
              const PillSegmented<int>(
                style: PillSegmentedStyle.onAccent,
                segments: [
                  PillSegment(value: 1, label: 'ОДИН'),
                  PillSegment(value: 2, label: 'ДВА'),
                ],
                value: 1,
                onChanged: null,
              ),
            ],
          ),
        ),
      );
      Color bg(String label) =>
          (tester
                      .widget<AnimatedContainer>(
                        find.ancestor(of: find.text(label), matching: find.byType(AnimatedContainer)),
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;

      expect(bg('АВТО'), RescueColors.text);
      expect(tester.widget<Text>(find.text('АВТО')).style!.color, RescueColors.onAccent);
      expect(tester.widget<Text>(find.text('МИМО')).style!.color, RescueColors.subOnDeep);
      expect(bg('ОДИН'), RescueColors.onAccent);
      expect(tester.widget<Text>(find.text('ОДИН')).style!.color, RescueColors.accent);

      await tester.tap(find.text('МИМО'));
      await tester.pump();
      expect(value, 'by');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(value, 'vpn');

      final segment = find.ancestor(of: find.text('VPN'), matching: find.byType(GestureDetector)).first;
      expect(tester.getSize(segment).height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel('Мимо VPN'), findsOneWidget);
    });
  });

  group('ServerSelect', () {
    const options = [
      ServerOption(value: 'nl', code: 'NL', name: 'Нидерланды', subtitle: 'first.gym-notes.ru', ping: '48 МС'),
      ServerOption(value: 'auto', code: 'A', name: 'Автовыбор', subtitle: 'самый быстрый', ping: 'АВТО'),
    ];

    testWidgets('раскрывается, выбирает и закрывается; «Добавить»', (tester) async {
      var value = 'nl';
      var added = 0;
      await pumpRescue(
        tester,
        StatefulBuilder(
          builder: (context, setState) => ServerSelect<String>(
            options: options,
            value: value,
            onChanged: (v) => setState(() => value = v),
            onAdd: () => added++,
          ),
        ),
      );
      final list = find.byKey(const ValueKey('server-select-list'));
      expect(find.text('Нидерланды'), findsOneWidget);
      expect(find.text('48 МС'), findsOneWidget);
      expect(list, findsNothing);
      expect(tester.getSize(find.byKey(const ValueKey('server-select-button'))).height, greaterThanOrEqualTo(64));

      await tester.tap(find.byKey(const ValueKey('server-select-button')));
      await tester.pump();
      expect(list, findsOneWidget);
      expect(find.text('Автовыбор'), findsOneWidget);
      expect(find.text('+ Добавить подписку или сервер'), findsOneWidget);

      await tester.tap(find.text('Автовыбор'));
      await tester.pumpAndSettle();
      expect(value, 'auto');
      expect(list, findsNothing);
      // В кнопке — выбранный.
      expect(find.text('Автовыбор'), findsOneWidget);
      expect(find.text('Нидерланды'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('server-select-button')));
      await tester.pump();
      await tester.tap(find.text('+ Добавить подписку или сервер'));
      expect(added, 1);
    });

    testWidgets('клавиатура: Enter раскрывает, Esc закрывает; Semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpRescue(tester, ServerSelect<String>(options: options, value: 'nl', onChanged: (_) {}));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      final list = find.byKey(const ValueKey('server-select-list'));
      expect(list, findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Сервер, Нидерланды')),
        containsSemantics(isButton: true, hasExpandedState: true, isExpanded: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Нидерланды, first.gym-notes.ru, 48 МС')),
        containsSemantics(isSelected: true),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(list, findsNothing);
      handle.dispose();
    });

    testWidgets('без выбранного — заглушка', (tester) async {
      await pumpRescue(tester, ServerSelect<String>(options: options, value: null, onChanged: (_) {}));
      expect(find.text('Сервер не выбран'), findsOneWidget);
    });
  });

  group('PowerButton', () {
    testWidgets('нажатие вызывает колбэк; подпись по состоянию; цвета на жёлтом', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await pumpRescue(
        tester,
        Wrap(
          children: [
            PowerButton(state: PowerState.on, onPressed: () => taps++),
            PowerButton(state: PowerState.off, onPressed: () => taps++, size: 120),
            PowerButton.mini(state: PowerState.on, onPressed: () => taps++),
          ],
        ),
      );
      await tester.tap(find.bySemanticsLabel('Отключить VPN').first);
      expect(taps, 1);
      await tester.tap(find.bySemanticsLabel('Подключить VPN'));
      expect(taps, 2);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Отключить VPN').first),
        containsSemantics(isButton: true, hasTapAction: true, isEnabled: true),
      );

      final big = find.byType(PowerButton).first;
      expect(tester.getSize(big), const Size(184, 184));
      final ink = tester.widget<Ink>(find.descendant(of: big, matching: find.byType(Ink)));
      final d = ink.decoration! as BoxDecoration;
      expect(d.color, RescueColors.ink);
      expect(d.border!.top.color, RescueColors.accentDeep);
      expect(d.border!.top.width, 12);
      final offInk = tester.widget<Ink>(
        find.descendant(of: find.byType(PowerButton).at(1), matching: find.byType(Ink)),
      );
      expect((offInk.decoration! as BoxDecoration).color, RescueColors.textOnDeep);

      // Мини: круг 40, зона нажатия 44, жёлтый при подключении.
      final mini = find.byType(PowerButton).last;
      expect(tester.getSize(mini), const Size(44, 44));
      final miniInk = tester.widget<Ink>(find.descendant(of: mini, matching: find.byType(Ink)));
      expect((miniInk.decoration! as BoxDecoration).color, RescueColors.accent);
      await tester.tap(mini);
      expect(taps, 3);
      handle.dispose();
    });

    testWidgets('подключение: крутится, подпись «Подключение…»; без колбэка неактивна', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpRescue(tester, const PowerButton(state: PowerState.connecting, onPressed: null, size: 120));
      expect(find.descendant(of: find.byType(PowerButton), matching: find.byType(RotationTransition)), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSemantics(find.bySemanticsLabel('Подключение…')), containsSemantics(isEnabled: false));
      // Ушли с «подключения» — вращение остановлено, pumpAndSettle завершается.
      await pumpRescue(tester, const PowerButton(state: PowerState.on, onPressed: null, size: 120));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(PowerButton), matching: find.byType(RotationTransition)), findsNothing);
      handle.dispose();
    });
  });

  group('ModeChip', () {
    testWidgets('переключается, цвета на жёлтом, высота 44, Semantics', (tester) async {
      final handle = tester.ensureSemantics();
      var on = true;
      await pumpRescue(
        tester,
        ColoredBox(
          color: RescueColors.accent,
          child: StatefulBuilder(
            builder: (context, setState) => ModeChip(
              label: 'Весь компьютер',
              hint: 'Все программы и игры',
              selected: on,
              onChanged: (v) => setState(() => on = v),
            ),
          ),
        ),
      );
      expect(tester.widget<Text>(find.text('Весь компьютер')).style!.color, RescueColors.accent);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Весь компьютер')),
        containsSemantics(isButton: true, hasToggledState: true, isToggled: true),
      );
      expect(tester.getSize(find.byType(ModeChip)).height, greaterThanOrEqualTo(44));
      await tester.tap(find.text('Весь компьютер'));
      await tester.pump();
      expect(on, isFalse);
      expect(tester.widget<Text>(find.text('Весь компьютер')).style!.color, RescueColors.onAccent);
      handle.dispose();
    });
  });

  group('RingStat', () {
    testWidgets('число, подпись, пояснение; Semantics одной фразой', (tester) async {
      await pumpRescue(
        tester,
        const Column(
          children: [
            RingStat(value: 0.35, label: '48', title: 'МС ПИНГ', caption: 'обычно 45–60'),
            RingStat(value: 1.5, label: '7', size: 40),
            RingStat.onAccent(value: null, label: '—', title: 'ГБ\nИЗ 200'),
          ],
        ),
      );
      expect(find.text('48'), findsOneWidget);
      expect(find.text('МС ПИНГ'), findsOneWidget);
      expect(find.text('обычно 45–60'), findsOneWidget);
      expect(find.bySemanticsLabel('48 МС ПИНГ, обычно 45–60'), findsOneWidget);
      expect(find.bySemanticsLabel('— ГБ ИЗ 200'), findsOneWidget);
      final ring = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is RingPainter);
      expect(tester.getSize(ring.first), const Size(52, 52));
      expect(tester.getSize(ring.at(1)), const Size(40, 40));
      final onAccent = tester.widget<CustomPaint>(ring.at(2)).painter! as RingPainter;
      expect(onAccent.trackColor, RescueColors.accentDeep);
      expect(onAccent.color, RescueColors.ink);
      expect(tester.takeException(), isNull);
    });
  });

  group('DeepList и DeepListTile', () {
    testWidgets('блок deep, заголовок с меткой, жёлтая строка, ссылка', (tester) async {
      var opened = 0;
      var picked = 0;
      await pumpRescue(
        tester,
        DeepList(
          title: 'Ошибки за час',
          count: '7',
          actionLabel: 'Все ошибки',
          onAction: () => opened++,
          children: [
            DeepListTile(
              leading: 'K',
              title: 'kinopoisk.ru',
              subtitle: 'Chrome · сброс',
              trailingText: '5',
              highlighted: true,
              onTap: () => picked++,
            ),
            const DeepListTile(leading: 'D', title: 'discord.gg', subtitle: 'обрыв', trailingText: '1'),
          ],
        ),
      );
      expect(find.text('ОШИБКИ ЗА ЧАС'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      final block = tester.widget<Container>(
        find.descendant(of: find.byType(DeepList), matching: find.byType(Container)).first,
      );
      expect((block.decoration! as BoxDecoration).color, RescueColors.deep);

      Material tileMaterial(String title) => tester.widget<Material>(
        find.descendant(of: find.widgetWithText(DeepListTile, title), matching: find.byType(Material)).first,
      );
      expect(tileMaterial('kinopoisk.ru').color, RescueColors.accent);
      expect(tester.widget<Text>(find.text('kinopoisk.ru')).style!.color, RescueColors.onAccent);
      expect(tileMaterial('discord.gg').color, Colors.transparent);
      expect(tester.widget<Text>(find.text('discord.gg')).style!.color, RescueColors.accent);
      expect(tester.getSize(find.byType(DeepListTile).first).height, greaterThanOrEqualTo(60));

      await tester.tap(find.text('kinopoisk.ru'));
      expect(picked, 1);
      await tester.tap(find.text('Все ошибки ›'));
      expect(opened, 1);
      expect(find.bySemanticsLabel('kinopoisk.ru, Chrome · сброс, 5'), findsOneWidget);
    });

    testWidgets('переключатель в хвосте строки доступен', (tester) async {
      var route = RouteChoice.auto;
      await pumpRescue(
        tester,
        StatefulBuilder(
          builder: (context, setState) => DeepList(
            children: [
              DeepListTile(
                leading: 'G',
                title: 'Google Chrome',
                highlighted: true,
                trailing: RouteSwitch(
                  value: route,
                  onAccent: true,
                  width: 200,
                  semanticLabel: 'Куда идёт Google Chrome',
                  onChanged: (r) => setState(() => route = r),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('VPN'));
      await tester.pump();
      expect(route, RouteChoice.vpn);
      expect(find.bySemanticsLabel('Через VPN'), findsOneWidget);
      expect(DeepTileColors.of(highlighted: true).ringTrack, RescueColors.accentDeep);
    });
  });

  testWidgets('StatColumns: подписи, числа, цветная линия слева', (tester) async {
    await pumpRescue(
      tester,
      const StatColumns(
        columns: [
          StatColumn(label: 'МИМО VPN', value: '38'),
          StatColumn(label: 'В СЕТИ', value: '4', lineColor: RescueColors.accent),
        ],
      ),
    );
    expect(find.text('38'), findsOneWidget);
    expect(find.bySemanticsLabel('В СЕТИ: 4'), findsOneWidget);
    final box = tester.widget<Container>(
      find.ancestor(of: find.text('В СЕТИ'), matching: find.byType(Container)).first,
    );
    final border = (box.decoration! as BoxDecoration).border! as Border;
    expect(border.left.color, RescueColors.accent);
    expect(border.left.width, 2);
  });

  testWidgets('SectionLabel: заглавные с разрядкой, метка-рамка, заголовок для чтеца', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRescue(
      tester,
      const Column(
        children: [
          SectionLabel('Серверы', count: '2'),
          SectionLabel.screen('Главная', trailing: Text('замеры раз в минуту')),
        ],
      ),
    );
    expect(find.text('СЕРВЕРЫ'), findsOneWidget);
    expect(find.text('ГЛАВНАЯ'), findsOneWidget);
    final style = tester.widget<Text>(find.text('ГЛАВНАЯ')).style!;
    expect(style.fontSize, 13);
    expect(style.letterSpacing, closeTo(2.34, 0.01));
    expect(tester.widget<Text>(find.text('СЕРВЕРЫ')).style!.letterSpacing, closeTo(1.68, 0.01));
    expect(find.byType(FrameTag), findsOneWidget);
    expect(tester.getSemantics(find.text('ГЛАВНАЯ')), containsSemantics(isHeader: true));
    expect(tester.getSize(find.byType(SectionLabel).last).height, greaterThanOrEqualTo(44));
    handle.dispose();
  });

  testWidgets('ShellStatusCard: статус и мини-кнопка', (tester) async {
    var taps = 0;
    await pumpRescue(
      tester,
      SizedBox(
        width: 232,
        child: ShellStatusCard(
          state: PowerState.on,
          title: 'Подключено',
          subtitle: 'Нидерланды · 48 мс',
          onPower: () => taps++,
        ),
      ),
    );
    expect(find.text('Подключено'), findsOneWidget);
    await tester.tap(find.byType(PowerButton));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RescueToggle: дорожка 46×28, жёлтая с тёмным кружком', (tester) async {
    await pumpRescue(tester, const Align(alignment: Alignment.topLeft, child: RescueToggle(value: true)));
    final track = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    expect((track.decoration! as BoxDecoration).color, RescueColors.accent);
    expect(tester.getSize(find.byType(AnimatedContainer)), const Size(46, 28));
  });

  test('палитра стиля «Д» и алиасы старых имён', () {
    expect(RescueColors.page, const Color(0xFF141311));
    expect(RescueColors.panel, const Color(0xFF1F1E1B));
    expect(RescueColors.card, const Color(0xFF2A2825));
    expect(RescueColors.deep, const Color(0xFF121110));
    expect(RescueColors.muted, const Color(0xFFA39B91));
    expect(RescueColors.accent, const Color(0xFFF4CC56));
    expect(RescueColors.background, RescueColors.panel);
    expect(RescueColors.textSecondary, RescueColors.muted);
    // Средне и плохо различимы (на них опираются отметки графика на Обзоре).
    expect(RescueColors.fair, isNot(RescueColors.poor));
  });
}
