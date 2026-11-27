import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/split_tunnel/data/tun_routes.dart';
import 'package:hiddify/features/split_tunnel/model/direct_routes.dart';
import 'package:hiddify/features/split_tunnel/notifier/direct_routes_notifier.dart';
import 'package:hiddify/features/split_tunnel/widget/tunnel_direct_view.dart';

import '../screens_test_helpers.dart';

class _Connected extends ConnectionNotifier {
  @override
  Stream<ConnectionStatus> build() async* {
    yield const Connected();
  }
}

class _FakeRoutes implements TunRoutes {
  final routes = <V4Net>{V4Net(0, 0)};

  @override
  Future<({int index, List<V4Net> routes})?> read() async => (index: 4, routes: routes.toList());

  @override
  Future<void> change(int index, {required List<V4Net> add, required List<V4Net> remove}) async {
    routes
      ..addAll(add)
      ..removeAll(remove);
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('direct_view_'));
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('add an address, apply now with confirmation, send it back to Шлюпка forever', (tester) async {
    final fake = _FakeRoutes();
    final container = (await tester.runAsync(
      () => screensContainer(
        dir,
        overrides: [
          connectionNotifierProvider.overrideWith(_Connected.new),
          tunRoutesProvider.overrideWithValue(fake),
          directRoutesEnabledProvider.overrideWithValue(true),
        ],
      ),
    ))!;
    container.listen(directRoutesProvider, (_, _) {});
    await pumpPage(
      tester,
      container,
      const Scaffold(body: SingleChildScrollView(child: TunnelDirectView())),
      size: const Size(1100, 1400),
    );
    await tester.pumpAndSettle();
    expect(find.text('Сети Blizzard'), findsOneWidget);
    expect(find.text('Всё применено.'), findsOneWidget, reason: 'the core got the list at connect');

    // Плохой адрес — ошибка в окне.
    await tester.tap(find.text('Добавить адрес или сеть…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '192.168.1.1');
    await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('домашний'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '35.228.147.76');
    await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
    await tester.pumpAndSettle();
    expect(find.text('35.228.147.76'), findsOneWidget);
    expect(find.textContaining('Есть изменения'), findsOneWidget);
    expect(File('${dir.path}/split/$tunExcludeFileName').readAsStringSync(), contains('35.228.147.76/32'));

    // «Применить сейчас»: сначала подтверждение, «Отмена» ничего не меняет.
    await tester.tap(find.text('Применить сейчас'));
    await tester.pumpAndSettle();
    expect(find.textContaining('игра может вылететь'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(fake.routes, {V4Net(0, 0)});
    await tester.tap(find.text('Применить сейчас'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Применить'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    final effective = container.read(directEffectiveProvider);
    expect(fake.routes, tunRouteRanges(effective).toSet());
    expect(find.text('Всё применено.'), findsOneWidget);

    // Своя запись — в группе «Добавлено вами».
    expect(
      find.descendant(of: find.byKey(const ValueKey('direct-group-')), matching: find.text('Добавлено вами')),
      findsOneWidget,
    );
    expect(find.text('ТОЛЬКО ЧЕРЕЗ ШЛЮПКУ'), findsOneWidget, reason: 'second column is always there');
    expect(find.text('Никогда мимо…'), findsNothing);

    // «Убрать и больше не добавлять» — запись уходит в «Только через Шлюпку».
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('direct-35.228.147.76/32')), matching: find.byTooltip('Действия')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Убрать и больше не добавлять'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('never-35.228.147.76/32')), findsOneWidget);
    expect(find.byKey(const ValueKey('direct-35.228.147.76/32')), findsNothing);
    expect(find.textContaining('Есть изменения'), findsOneWidget);

    // Обратно: «Вернуть в «Мимо Шлюпки»» — снова своя запись, запрета нет.
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('never-35.228.147.76/32')), matching: find.byTooltip('Действия')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Вернуть в «Мимо Шлюпки»'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('never-35.228.147.76/32')), findsNothing);
    expect(find.byKey(const ValueKey('direct-35.228.147.76/32')), findsOneWidget);
    expect(container.read(directRoutesProvider).never, isEmpty);

    // Таймер запоминания живёт, пока VPN включён: закрываем, как при выходе из программы.
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}
