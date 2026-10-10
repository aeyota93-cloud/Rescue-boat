import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/model/optional_range.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/actions_at_closing.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/insights/notifier/insights_settings.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/advanced_settings_page.dart';
import 'package:hiddify/features/settings/widget/rescue_settings_page.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../screens_test_helpers.dart';
import '../shell_frame_helper.dart';

class _FakeAutoStart extends AutoStartNotifier {
  final calls = <bool>[];

  @override
  Future<bool> build() async => false;

  @override
  Future<void> enable() async {
    calls.add(true);
    state = const AsyncData(true);
  }

  @override
  Future<void> disable() async {
    calls.add(false);
    state = const AsyncData(false);
  }
}

class _FakeAppInfo extends AppInfo {
  @override
  Future<AppInfoEntity> build() async => const AppInfoEntity(
    name: 'Шлюпка спасения',
    version: '0.2.0',
    buildNumber: '1',
    release: Release.general,
    operatingSystem: 'windows',
    operatingSystemVersion: '11',
    environment: Environment.prod,
  );
}

void main() {
  late Directory dir;
  late _FakeAutoStart autoStart;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rescue_settings_');
    autoStart = _FakeAutoStart();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<ProviderContainer> start(WidgetTester tester, {Size size = const Size(1440, 1000), bool inShell = false}) async {
    final container = await tester.runAsync(
      () => screensContainer(
        dir,
        overrides: [
          autoStartNotifierProvider.overrideWith(() => autoStart),
          appInfoProvider.overrideWith(_FakeAppInfo.new),
        ],
      ),
    );
    if (inShell) {
      await pumpInShell(tester, container!, const RescueSettingsPage(), size: size, selected: 4);
    } else {
      await pumpPage(tester, container!, const RescueSettingsPage(), size: size);
    }
    return container;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  for (final size in shellSizes) {
    testWidgets('отрисовка, окно ${size.width.toInt()} px: все блоки, без переполнений', (tester) async {
      final container = await start(tester, size: size, inShell: true);
      expectNoLayoutErrors(tester);
      expect(find.text('НАСТРОЙКИ'), findsOneWidget);
      for (final title in [
        'ЗАПУСК',
        'КУДА ИДЁТ ТРАФИК',
        'ОШИБКИ И ЗДОРОВЬЕ',
        'СПОСОБ РАБОТЫ',
        'ОБХОД БЛОКИРОВОК',
        'ДЛЯ ОПЫТНЫХ',
      ]) {
        expect(find.text(title), findsWidgets, reason: title);
      }
      expect(find.textContaining('Шлюпка спасения 0.2.0 · основано на Hiddify'), findsOneWidget);
      expect(find.text('Уведомление Windows при обрыве связи'), findsNothing);
      // «Для опытных» прямо в настройках: четыре ссылки как в макете и переход ко всем.
      for (final link in advancedLinks.take(4)) {
        expect(find.text(link.title), findsOneWidget, reason: link.title);
      }
      expect(find.text('Все настройки для опытных'), findsOneWidget);
      // Переключатели — RescueToggle 46×28.
      expect(find.byType(RescueToggle), findsNWidgets(11));
      expect(tester.getSize(find.byType(RescueToggle).first), const Size(46, 28));

      // Фрагментация с параметрами тоже помещается.
      await tapText(tester, 'Делить начало соединения (фрагментация)');
      expect(find.text('Размер кусков, байт'), findsOneWidget);
      expectNoLayoutErrors(tester);
      await closePage(tester, container);
    });
  }

  testWidgets('переключатели меняют свои настройки', (tester) async {
    final container = await start(tester);

    expect(container.read(ConfigOptions.region), Region.ru);
    await tapText(tester, 'Российские сайты напрямую');
    expect(container.read(ConfigOptions.region), Region.other);
    await tapText(tester, 'Российские сайты напрямую');
    expect(container.read(ConfigOptions.region), Region.ru);

    expect(container.read(ConfigOptions.bypassLan), isTrue);
    await tapText(tester, 'Домашняя сеть мимо VPN');
    expect(container.read(ConfigOptions.bypassLan), isFalse);

    await tapText(tester, 'Собирать ошибки соединений');
    expect(container.read(insightsSettingsProvider).collectErrors, isFalse);
    await tapText(tester, 'Замерять пинг');
    expect(container.read(insightsSettingsProvider).measurePing, isFalse);

    await tapText(tester, 'Только браузеры');
    expect(container.read(ConfigOptions.serviceMode), ServiceMode.systemProxy);
    await tapText(tester, 'Весь компьютер');
    expect(container.read(ConfigOptions.serviceMode), ServiceMode.tun);

    await tapText(tester, 'Запускать при входе в Windows');
    expect(autoStart.calls, [true]);

    await tapText(tester, 'Сворачивать в трей при закрытии');
    expect(container.read(Preferences.actionAtClose), ActionsAtClosing.hide);

    await tapText(tester, 'Запускать свёрнутым');
    expect(container.read(Preferences.silentStart), isTrue);

    await tapText(tester, 'Смешанный регистр имени сайта');
    expect(container.read(ConfigOptions.enableTlsMixedSniCase), isTrue);

    await tapText(tester, 'Делить начало соединения (фрагментация)');
    expect(container.read(ConfigOptions.enableTlsFragment), isTrue);
    final sizeField = find.descendant(
      of: find.ancestor(of: find.text('Размер кусков, байт'), matching: find.byType(Wrap)).first,
      matching: find.byType(TextField),
    );
    await tester.enterText(sizeField, '5-15');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(container.read(ConfigOptions.tlsFragmentSize), const OptionalRange(min: 5, max: 15));
    // Неверное значение не сохраняется.
    await tester.enterText(sizeField, 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(container.read(ConfigOptions.tlsFragmentSize), const OptionalRange(min: 5, max: 15));

    await closePage(tester, container);
  });

  testWidgets('«Игры и лаунчеры мимо VPN»: выкл убирает игры из списков, вкл возвращает', (tester) async {
    final container = await start(tester);
    SplitTunnel state() => container.read(splitTunnelProvider);
    // По умолчанию на Windows игры в «мимо VPN».
    expect(defaultGamesInBypass(state().bypass.apps), defaultBypassApps.length);

    // Одна игра перенесена в «через VPN» и одна своя программа в «мимо» — свою не трогаем.
    container.read(splitTunnelProvider.notifier)
      ..add(SplitTarget.via, SplitKind.app, 'cs2.exe')
      ..add(SplitTarget.bypass, SplitKind.app, 'my.exe');
    await tester.pumpAndSettle();

    await tapText(tester, 'Игры и лаунчеры мимо VPN');
    expect(defaultGamesInBypass(state().bypass.apps), 0);
    expect(state().via.apps, isNot(contains('cs2.exe')));
    expect(state().bypass.apps, ['my.exe']);

    await tapText(tester, 'Игры и лаунчеры мимо VPN');
    expect(defaultGamesInBypass(state().bypass.apps), defaultBypassApps.length);
    expect(state().bypass.apps, contains('my.exe'));

    await closePage(tester, container);
  });

  testWidgets('«Для опытных»: ссылки на прежние страницы', (tester) async {
    final container = await tester.runAsync(() => screensContainer(dir));
    await pumpInShell(tester, container!, const AdvancedSettingsPage(), size: const Size(900, 900), selected: 4);
    expectNoLayoutErrors(tester);
    expect(find.text('ДЛЯ ОПЫТНЫХ'), findsOneWidget);
    expect(find.byTooltip('Назад'), findsOneWidget);
    for (final link in advancedLinks) {
      expect(find.text(link.title), findsOneWidget);
    }
    expect(
      advancedLinks.map((l) => l.routeName),
      containsAll(['logs', 'routeOptions', 'dnsOptions', 'inboundOptions', 'about']),
    );
    await closePage(tester, container);
  });
}
