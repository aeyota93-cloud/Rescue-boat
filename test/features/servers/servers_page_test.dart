import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show Unit, unit;
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/servers/model/servers_format.dart';
import 'package:hiddify/features/servers/widget/servers_page.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../screens_test_helpers.dart';
import '../shell_frame_helper.dart';

const _gb = 1024 * 1024 * 1024;

class _FakeProfiles extends ProfilesNotifier {
  _FakeProfiles(this.list);

  final List<ProfileEntity> list;
  final selected = <String>[];
  final deleted = <String>[];

  @override
  Stream<List<ProfileEntity>> build() => Stream.value(list);

  @override
  Future<Unit> selectActiveProfile(String id) async {
    selected.add(id);
    return unit;
  }

  @override
  Future<void> deleteProfile(ProfileEntity profile) async => deleted.add(profile.id);
}

class _FakeProxies extends ProxiesOverviewNotifier {
  _FakeProxies(this.group, {this.error});

  final OutboundGroup? group;
  final Object? error;
  final changed = <String>[];
  final tested = <String>[];

  @override
  Stream<OutboundGroup?> build() => error != null ? Stream.error(error!) : Stream.value(group);

  @override
  Future<void> changeProxy(String groupTag, String outboundTag) async => changed.add('$groupTag/$outboundTag');

  @override
  Future<void> urlTest(String groupTag) async => tested.add(groupTag);
}

class _FakeAdd extends AddProfileNotifier {
  final added = <String>[];

  @override
  AsyncValue<Unit?> build() => const AsyncData(null);

  @override
  Future<void> addClipboard(String rawInput) async => added.add(rawInput);
}

class _FakeUpdate extends UpdateProfileNotifier {
  @override
  AsyncValue<Unit?> build(String id) => const AsyncData(null);
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('servers_page_'));
  tearDown(() => dir.deleteSync(recursive: true));

  final now = DateTime.now();
  final main = RemoteProfileEntity(
    id: 'p1',
    active: true,
    name: 'Основной',
    url: 'https://example.com/sub',
    lastUpdate: now,
    options: const ProfileOptions(updateInterval: Duration(hours: 6)),
    subInfo: SubscriptionInfo(
      upload: 0,
      download: 48 * _gb,
      total: 200 * _gb,
      expire: now.add(const Duration(days: 31, hours: 1)),
    ),
  );
  final local = LocalProfileEntity(id: 'p2', active: false, name: 'Домашний', lastUpdate: now);

  OutboundGroup servers() => OutboundGroup(
    tag: 'select',
    type: 'selector',
    selected: 'nl',
    items: [
      OutboundInfo(tag: 'auto', type: 'urltest', urlTestDelay: 48, isGroup: true, tagDisplay: 'Автовыбор'),
      OutboundInfo(tag: 'nl', type: 'vless', urlTestDelay: 120, tagDisplay: 'Нидерланды', host: 'first.example'),
      OutboundInfo(tag: 'de', type: 'trojan', urlTestDelay: 70000, tagDisplay: 'Германия'),
    ],
  );

  final health = HealthSnapshot(
    overall: const HealthMetric(title: 'Общая оценка', score: 92, good: 0.8, fair: 0.14, poor: 0.06, caption: ''),
    ping: HealthSnapshot.empty.ping,
    stability: HealthSnapshot.empty.stability,
    errorsFree: HealthSnapshot.empty.errorsFree,
    dns: HealthSnapshot.empty.dns,
    pingMs: 48,
    jitterMs: 3,
    lossPercent: 0,
  );

  Future<ProviderContainer> start(
    WidgetTester tester, {
    required _FakeProfiles profiles,
    required _FakeProxies proxies,
    _FakeAdd? add,
    Size size = const Size(1440, 1000),
    bool inShell = false,
  }) async {
    final container = await tester.runAsync(
      () => screensContainer(
        dir,
        overrides: [
          profilesNotifierProvider.overrideWith(() => profiles),
          proxiesOverviewNotifierProvider.overrideWith(() => proxies),
          addProfileNotifierProvider.overrideWith(() => add ?? _FakeAdd()),
          for (final p in profiles.list) updateProfileNotifierProvider(p.id).overrideWith(_FakeUpdate.new),
          healthProvider.overrideWith((ref) => AsyncData(health)),
        ],
      ),
    );
    if (inShell) {
      await pumpInShell(tester, container!, const ServersPage(), size: size, selected: 3);
    } else {
      await pumpPage(tester, container!, const ServersPage(), size: size);
    }
    return container;
  }

  Future<void> tapText(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('подписи', () {
    test('гигабайты, даты, протоколы, пинг', () {
      expect(formatGb(48 * _gb), '48');
      expect(formatGb(_gb * 3 ~/ 2), '1,5');
      expect(formatGb(2 * _gb), '2');
      expect(ruDate(DateTime(2026, 11, 9, 12)), '9 ноября');
      expect(daysLeftLabel(DateTime(2026, 11, 9, 12), DateTime(2026, 10, 9, 10)), 'ещё 31 день');
      expect(daysLeftLabel(DateTime(2026, 10, 2), DateTime(2026, 10, 9)), 'истекла');
      expect(updatedLabel(DateTime(2026, 10, 9, 12, 40), DateTime(2026, 10, 9, 18)), '12:40');
      expect(updatedLabel(DateTime(2026, 10, 8, 12, 40), DateTime(2026, 10, 9, 18)), '8 октября');
      expect(protocolName('vless'), 'VLESS');
      expect(protocolName('urltest'), 'Автовыбор');
      expect(pingLabel(0), '—');
      expect(pingLabel(48), '48 мс');
      expect(pingLabel(70000), 'нет ответа');
      expect(autoUpdateLabel(main), 'сама, раз в 6 часов');
      expect(autoUpdateLabel(local), 'конфиг без ссылки');
      expect(serverCode('🇳🇱 Нидерланды'), 'NL');
      expect(serverCode('Автовыбор'), 'А');
      expect(serverCode('  ★ fast-1'), 'F');
      expect(serverTitle('🇳🇱 Нидерланды'), 'Нидерланды');
      expect(serverTitle('🇳🇱'), '🇳🇱');
      expect(subscriptionHost('https://first.example.com/sub/SECRET?x=1'), 'first.example.com');
      expect(subscriptionHost('не ссылка'), isNull);
      expect(pingSpeedFraction(0), 0);
      expect(pingSpeedFraction(70000), 0);
      expect(pingSpeedFraction(30), closeTo(0.9, 0.001));
    });
  });

  for (final size in shellSizes) {
    testWidgets('с данными, окно ${size.width.toInt()} px: подписка, запасной, серверы, без переполнений', (
      tester,
    ) async {
      final container = await start(
        tester,
        profiles: _FakeProfiles([main, local]),
        proxies: _FakeProxies(servers()),
        size: size,
        inShell: true,
      );
      expectNoLayoutErrors(tester);
      final semantics = tester.ensureSemantics();

      expect(find.text('ПОДПИСКИ И СЕРВЕРЫ'), findsOneWidget);
      expect(find.text('Основной'), findsOneWidget);
      expect(find.text('АКТИВНА'), findsOneWidget);
      // Кольца: расход, срок, автообновление — числа внутри и подписи для чтеца.
      expect(find.text('ГБ\nИЗ 200'), findsOneWidget);
      expect(find.text('31'), findsOneWidget);
      expect(find.text('ДЕНЬ\nОСТАЛОСЬ'), findsOneWidget);
      expect(find.text('6ч'), findsOneWidget);
      expect(find.bySemanticsLabel('Израсходовано 48 из 200 ГБ'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Действует до .*, ещё 31 день$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Обновляется сама, раз в 6 часов, обновлена ')), findsOneWidget);
      expect(find.textContaining('example.com · до '), findsOneWidget);
      expect(find.text('Запасной'), findsOneWidget);
      expect(find.text('Добавить подписку'), findsWidgets);
      expect(find.text('Автоматическое переключение на запасной сервер появится в следующей версии.'), findsOneWidget);
      expect(find.text('ДРУГИЕ ПОДПИСКИ'), findsOneWidget);
      expect(find.text('Домашний'), findsOneWidget);

      expect(find.text('Нидерланды'), findsOneWidget);
      expect(find.text('VLESS'), findsOneWidget);
      expect(find.text('120 МС'), findsOneWidget);
      expect(find.text('НЕТ ОТВЕТА'), findsOneWidget);
      // Здоровье — только у выбранного сервера.
      expect(find.text('92'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Нидерланды, VLESS, пинг 120 мс, здоровье за сутки 92, выбран$')),
        findsOneWidget,
      );
      semantics.dispose();
      await closePage(tester, container);
    });
  }

  group('много серверов (40)', () {
    OutboundGroup manyServers() => OutboundGroup(
      tag: 'select',
      type: 'selector',
      selected: 'srv0',
      items: [
        for (var i = 0; i < 40; i++)
          OutboundInfo(tag: 'srv$i', type: 'vless', urlTestDelay: 50 + i, tagDisplay: 'Сервер $i', host: 'h$i.example'),
      ],
    );

    Rect rect(WidgetTester tester, Finder f) => tester.getRect(f.first);

    void expectOnScreen(WidgetTester tester, Finder f, Size window, String what) {
      expect(f, findsWidgets, reason: what);
      final r = rect(tester, f);
      expect(r.top, greaterThanOrEqualTo(0), reason: '$what сверху: $r');
      expect(r.bottom, lessThanOrEqualTo(window.height), reason: '$what снизу: $r');
      expect(r.right, lessThanOrEqualTo(window.width), reason: '$what справа: $r');
    }

    testWidgets('1440×900: шапка и активная подписка на месте, остальное крутится в своей области', (tester) async {
      const window = Size(1440, 900);
      final container = await start(
        tester,
        profiles: _FakeProfiles([main, local]),
        proxies: _FakeProxies(manyServers()),
        size: window,
      );
      expectNoLayoutErrors(tester);

      final fixed = {
        'заголовок': find.text('ПОДПИСКИ И СЕРВЕРЫ'),
        'проверить пинг': find.text('Проверить пинг'),
        'добавить подписку': find.text('+ Добавить подписку'),
        'название подписки': find.text('Основной'),
        'метка': find.text('АКТИВНА'),
        'обновить': find.text('Обновить'),
        'удалить': find.text('Удалить').first,
      };
      for (final e in fixed.entries) {
        expectOnScreen(tester, e.value, window, e.key);
      }
      final before = {for (final e in fixed.entries) e.key: rect(tester, e.value)};
      final others = rect(tester, find.text('ДРУГИЕ ПОДПИСКИ'));

      final scroll = find.byKey(const ValueKey('servers-scroll'));
      final scrollable = find.descendant(of: scroll, matching: find.byType(Scrollable)).first;
      expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
      await tester.drag(scrollable, const Offset(0, -3000));
      await tester.pump();
      expect(tester.state<ScrollableState>(scrollable).position.pixels, greaterThan(0));
      expect(find.text('Запасной'), findsOneWidget, reason: 'конец списка достижим');
      expect(rect(tester, find.text('Запасной')).bottom, lessThanOrEqualTo(window.height));

      for (final e in fixed.entries) {
        expect(rect(tester, e.value), before[e.key], reason: '${e.key} не сдвинулся(ась) от прокрутки');
      }
      expect(
        find.text('ДРУГИЕ ПОДПИСКИ').evaluate().isEmpty || rect(tester, find.text('ДРУГИЕ ПОДПИСКИ')) != others,
        isTrue,
      );
      expectNoLayoutErrors(tester);
      await closePage(tester, container);
    });

    testWidgets('420×700: прокручивается вся страница, серверов сначала 30, «Показать ещё»', (tester) async {
      final container = await start(
        tester,
        profiles: _FakeProfiles([main, local]),
        proxies: _FakeProxies(manyServers()),
        size: const Size(420, 700),
      );
      expectNoLayoutErrors(tester);
      expect(find.byKey(const ValueKey('servers-scroll')), findsNothing);

      final page = find.byType(Scrollable).first;
      final more = find.byKey(const ValueKey('servers-more'));
      await tester.scrollUntilVisible(more, 300, scrollable: page);
      expect(find.text('Показать ещё · 30 из 40'), findsOneWidget);
      expect(find.text('Сервер 29'), findsOneWidget);
      expect(find.text('Сервер 30'), findsNothing);
      await tester.tap(more);
      await tester.pump();
      expect(find.text('Сервер 39'), findsOneWidget);
      expect(more, findsNothing);
      await tester.drag(page, const Offset(0, -9000));
      await tester.pump();
      expect(find.text('Запасной'), findsOneWidget);
      expectNoLayoutErrors(tester);
      await closePage(tester, container);
    });

    testWidgets('860×600: нет переполнений, пустой список подписок тоже', (tester) async {
      for (final profiles in [
        <ProfileEntity>[main, local],
        <ProfileEntity>[],
      ]) {
        final container = await start(
          tester,
          profiles: _FakeProfiles(profiles),
          proxies: _FakeProxies(manyServers()),
          size: const Size(860, 600),
        );
        expectNoLayoutErrors(tester);
        expect(find.byKey(const ValueKey('servers-scroll')), findsOneWidget);
        await closePage(tester, container);
      }
    });
  });

  testWidgets('выбор сервера, проверка пинга, активная подписка, удаление с подтверждением', (tester) async {
    final profiles = _FakeProfiles([main, local]);
    final proxies = _FakeProxies(servers());
    final container = await start(tester, profiles: profiles, proxies: proxies);

    await tapText(tester, find.text('Автовыбор'));
    expect(proxies.changed, ['select/auto']);

    await tapText(tester, find.text('Проверить пинг'));
    expect(proxies.tested, ['select']);

    await tapText(tester, find.text('Сделать активной'));
    expect(profiles.selected, ['p2']);

    // Первая «Удалить» — у активной подписки; без подтверждения ничего не удаляется.
    await tapText(tester, find.text('Удалить').first);
    expect(find.text('Удалить подписку «Основной»?'), findsOneWidget);
    await tapText(tester, find.text('Отмена'));
    expect(profiles.deleted, isEmpty);

    await tapText(tester, find.text('Удалить').first);
    await tapText(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Удалить')));
    expect(profiles.deleted, ['p1']);

    await closePage(tester, container);
  });

  testWidgets('добавление подписки по ссылке', (tester) async {
    final add = _FakeAdd();
    final container = await start(tester, profiles: _FakeProfiles([main]), proxies: _FakeProxies(servers()), add: add);

    await tapText(tester, find.text('+ Добавить подписку'));
    expect(find.text('Вставить из буфера'), findsOneWidget);
    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      ' https://example.org/s ',
    );
    await tester.pump();
    await tapText(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Добавить')));
    expect(add.added, ['https://example.org/s']);

    await closePage(tester, container);
  });

  testWidgets('пусто и VPN выключен', (tester) async {
    final container = await start(
      tester,
      profiles: _FakeProfiles(const []),
      proxies: _FakeProxies(null, error: const ServiceNotRunning()),
      size: const Size(900, 900),
      inShell: true,
    );
    expectNoLayoutErrors(tester);
    expect(find.text('Подписок пока нет'), findsOneWidget);
    expect(find.text('Запасной'), findsOneWidget);
    expect(find.text('Список серверов и пинг видны, когда VPN подключён.'), findsOneWidget);
    final check = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Проверить пинг'));
    expect(check.onPressed, isNull);
    await closePage(tester, container);
  });
}
