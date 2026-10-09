import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/rescue_ui/gallery_page.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';

import 'helpers.dart';

void main() {
  // Витрина строится целиком (без ленивых списков), поэтому переполнение любой части
  // упадёт в тесте как ошибка рендеринга.
  for (final size in const [Size(400, 900), Size(700, 900), Size(1440, 1000)]) {
    testWidgets('витрина без переполнений на ${size.width.toInt()} px', (tester) async {
      setWindowSize(tester, size);
      await tester.pumpWidget(const MaterialApp(home: RescueGalleryPage()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Все кирпичики на месте.
      for (final type in [
        RescueShell,
        RescueCard,
        SectionHeader,
        ScoreRow,
        StatTile,
        RescueBadge,
        RouteSwitch,
        ConnectionPill,
        RescueTable,
        DonutChart,
        LineChart,
        HourBars,
        FilterChips,
        PeriodSwitch,
        SettingsSwitchTile,
        ChoiceCard,
      ]) {
        expect(
          find.byWidgetPredicate((w) => w.runtimeType.toString().split('<').first == type.toString().split('<').first),
          findsWidgets,
          reason: '$type',
        );
      }
    });
  }

  testWidgets('витрина живая: RouteSwitch в таблице меняет счётчик', (tester) async {
    setWindowSize(tester, const Size(1440, 1000));
    await tester.pumpWidget(const MaterialApp(home: RescueGalleryPage()));
    final viaTile = find.widgetWithText(StatTile, 'Через VPN');
    String viaValue() => tester.widget<StatTile>(viaTile).value;
    expect(viaValue(), '1');

    final chromeSwitch = find.byWidgetPredicate(
      (w) => w is RouteSwitch && w.semanticLabel == 'Куда идёт Google Chrome',
    );
    await tester.ensureVisible(chromeSwitch);
    await tester.tap(find.descendant(of: chromeSwitch, matching: find.text('VPN')));
    await tester.pumpAndSettle();
    expect(viaValue(), '2');
  });
}
