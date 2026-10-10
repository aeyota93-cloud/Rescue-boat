import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/model/optional_range.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/actions_at_closing.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/common/rescue_page_header.dart';
import 'package:hiddify/features/insights/notifier/insights_settings.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/advanced_settings_page.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/model/tunnel_rows.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Имя маршрута страницы «Для опытных» (/settings/advanced) — его добавляет основная сессия.
const advancedSettingsRouteName = 'advancedSettings';

/// Переход по имени маршрута; если такого маршрута нет — открыть [fallback] поверх.
void openRescueRoute(BuildContext context, String name, {Widget? fallback}) {
  try {
    context.goNamed(name);
  } catch (_) {
    if (fallback != null) Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => fallback));
  }
}

/// Шлюпка: «Настройки» в стиле «Д». Всё сохраняется сразу; изменения, которым нужно
/// переподключение, применяет ConnectionWrapper сам.
///
/// Сетка карточек (от 380 px): Запуск, Куда идёт трафик, Ошибки и здоровье, Обход блокировок,
/// Способ работы и тёмный блок «Для опытных» со ссылками на прежние экраны Hiddify.
class RescueSettingsPage extends HookConsumerWidget {
  const RescueSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appInfoProvider).valueOrNull?.presentVersion;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RescuePageHeader(title: 'Настройки'),
            const SizedBox(height: 20),
            const RescueGrid(
              minItemWidth: 380,
              spacing: 20,
              children: [
                _StartupSection(),
                _TrafficSection(),
                _InsightsSection(),
                _BypassBlocksSection(),
                _ModeSection(),
                _AdvancedSection(),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  'Шлюпка спасения${version == null ? '' : ' $version'} · основано на Hiddify · '
                  'ничего не отправляет разработчикам',
                  style: RescueText.caption,
                ),
                RescueLink(label: 'О программе', onTap: () => openRescueRoute(context, 'about')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка-секция со списком переключателей (как в макете: card, радиус 32, отступ 10/22,
/// подпись блока заглавными 12 / 700 / 0.14em).
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.note});

  final String title;
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    return RescueCard(
      semanticLabel: title,
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 2),
            child: SectionLabel(title),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(note, style: RescueText.caption),
            ),
          ...children,
        ],
      ),
    );
  }
}

// ---------- Запуск ----------

class _StartupSection extends HookConsumerWidget {
  const _StartupSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoStart = ref.watch(autoStartNotifierProvider);
    final silent = ref.watch(Preferences.silentStart);
    final closing = ref.watch(Preferences.actionAtClose);
    final busy = useState(false);

    Future<void> setAutoStart(bool value) async {
      busy.value = true;
      try {
        final notifier = ref.read(autoStartNotifierProvider.notifier);
        await (value ? notifier.enable() : notifier.disable());
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Не удалось изменить автозапуск. Нужны права администратора.')));
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return _Section(
      title: 'Запуск',
      children: [
        SettingsSwitchTile(
          title: 'Запускать при входе в Windows',
          subtitle: 'Без окна «Разрешить изменения?»',
          value: autoStart.valueOrNull ?? false,
          onChanged: busy.value || !autoStart.hasValue ? null : setAutoStart,
        ),
        SettingsSwitchTile(
          title: 'Запускать свёрнутым',
          subtitle: 'Окно не открывается, программа ждёт в трее',
          value: silent,
          onChanged: ref.read(Preferences.silentStart.notifier).update,
        ),
        SettingsSwitchTile(
          title: 'Сворачивать в трей при закрытии',
          subtitle: switch (closing) {
            ActionsAtClosing.hide => 'Крестик не выключает VPN',
            ActionsAtClosing.ask => 'Сейчас спрашивает при каждом закрытии',
            ActionsAtClosing.exit => 'Сейчас крестик закрывает программу и VPN',
          },
          value: closing == ActionsAtClosing.hide,
          onChanged: (v) =>
              ref.read(Preferences.actionAtClose.notifier).update(v ? ActionsAtClosing.hide : ActionsAtClosing.ask),
          divider: false,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('VPN включится сам при запуске, если был включён при выходе.', style: RescueText.caption),
        ),
      ],
    );
  }
}

// ---------- Куда идёт трафик ----------

class _TrafficSection extends ConsumerWidget {
  const _TrafficSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final region = ref.watch(ConfigOptions.region);
    final bypassLan = ref.watch(ConfigOptions.bypassLan);
    final bypassApps = ref.watch(splitTunnelProvider.select((s) => s.bypass.apps));
    final games = defaultGamesInBypass(bypassApps);
    final total = defaultBypassApps.length;
    return _Section(
      title: 'Куда идёт трафик',
      children: [
        SettingsSwitchTile(
          title: 'Российские сайты напрямую',
          subtitle: 'Банки и Госуслуги видят домашний IP',
          value: region == Region.ru,
          onChanged: (v) => ref.read(ConfigOptions.region.notifier).update(v ? Region.ru : Region.other),
        ),
        SettingsSwitchTile(
          title: 'Домашняя сеть мимо VPN',
          subtitle: 'Принтер, роутер, телевизор',
          value: bypassLan,
          onChanged: ref.read(ConfigOptions.bypassLan.notifier).update,
        ),
        SettingsSwitchTile(
          title: 'Игры и лаунчеры мимо VPN',
          subtitle: games == total || games == 0
              ? '$total ${pluralRu(total, 'программа', 'программы', 'программ')}, их видно в раздельном туннеле'
              : '$games из $total ${pluralRu(total, 'программы', 'программ', 'программ')}, их видно в раздельном туннеле',
          value: games > 0,
          onChanged: (v) => setDefaultGamesBypass(ref.read(splitTunnelProvider.notifier), v),
          divider: false,
        ),
      ],
    );
  }
}

/// Сколько игр и лаунчеров по умолчанию сейчас в списке «мимо VPN».
int defaultGamesInBypass(List<String> bypassApps) {
  final have = {for (final a in bypassApps) a.toLowerCase()};
  return defaultBypassApps.where((a) => have.contains(a.toLowerCase())).length;
}

/// Включить — добавить недостающие игры в «мимо VPN» (из «через VPN» они уходят);
/// выключить — убрать их из обоих списков, решают общие правила.
void setDefaultGamesBypass(SplitTunnelNotifier notifier, bool enabled) => enabled
    ? notifier.addAll(SplitTarget.bypass, SplitKind.app, defaultBypassApps)
    : notifier.removeEverywhere(SplitKind.app, defaultBypassApps);

// ---------- Ошибки и здоровье ----------

class _InsightsSection extends ConsumerWidget {
  const _InsightsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(insightsSettingsProvider);
    final notifier = ref.read(insightsSettingsProvider.notifier);
    return _Section(
      title: 'Ошибки и здоровье',
      children: [
        SettingsSwitchTile(
          title: 'Собирать ошибки соединений',
          subtitle: 'Хранятся 7 дней только на этом компьютере',
          value: settings.collectErrors,
          onChanged: notifier.setCollectErrors,
        ),
        SettingsSwitchTile(
          title: 'Замерять пинг',
          subtitle: 'Раз в минуту, пока VPN включён; хранится 30 дней',
          value: settings.measurePing,
          onChanged: notifier.setMeasurePing,
          divider: false,
        ),
      ],
    );
  }
}

// ---------- Способ работы ----------

class _ModeSection extends ConsumerWidget {
  const _ModeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(ConfigOptions.serviceMode);
    final notifier = ref.read(ConfigOptions.serviceMode.notifier);
    return RescueCard(
      semanticLabel: 'Способ работы',
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Способ работы'),
          const SizedBox(height: 12),
          ChoiceCard(
            title: 'Весь компьютер',
            description: 'Все программы и игры, работают раздельный туннель и список ошибок',
            selected: mode == ServiceMode.tun,
            onTap: () => notifier.update(ServiceMode.tun),
          ),
          const SizedBox(height: 12),
          ChoiceCard(
            title: 'Только браузеры',
            description: 'Режим прокси: без прав администратора, остальные программы идут напрямую',
            selected: mode != ServiceMode.tun,
            onTap: () => notifier.update(ServiceMode.systemProxy),
          ),
        ],
      ),
    );
  }
}

// ---------- Обход блокировок ----------

const _fragmentPackets = {
  'tlshello': 'Приветствие TLS (обычно хватает)',
  '1-1': 'Первый пакет',
  '1-2': 'Первые 2 пакета',
  '1-3': 'Первые 3 пакета',
  '1-4': 'Первые 4 пакета',
  '1-5': 'Первые 5 пакетов',
};

class _BypassBlocksSection extends ConsumerWidget {
  const _BypassBlocksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fragment = ref.watch(ConfigOptions.enableTlsFragment);
    final packets = ref.watch(ConfigOptions.fragmentPackets);
    final mixedCase = ref.watch(ConfigOptions.enableTlsMixedSniCase);
    final padding = ref.watch(ConfigOptions.enableTlsPadding);
    return _Section(
      title: 'Обход блокировок',
      note:
          'Нужно, только если провайдер мешает: сайты напрямую не открываются или сервер не подключается. '
          'Обычно всё выключено.',
      children: [
        SettingsSwitchTile(
          title: 'Делить начало соединения (фрагментация)',
          subtitle:
              'Фильтр провайдера не видит имя сайта целиком. Действует на прямые соединения и на серверы '
              'с WebSocket или gRPC. Сайты могут открываться чуть медленнее.',
          value: fragment,
          onChanged: ref.read(ConfigOptions.enableTlsFragment.notifier).update,
        ),
        if (fragment)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ParamRow(
                  title: 'Что делить',
                  subtitle: 'Если не помогает — попробуйте первые несколько пакетов',
                  child: SizedBox(
                    width: 240,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _fragmentPackets.containsKey(packets) ? packets : 'tlshello',
                        isDense: true,
                        isExpanded: true,
                        dropdownColor: RescueColors.card,
                        style: RescueText.small,
                        items: [
                          for (final e in _fragmentPackets.entries)
                            DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) ref.read(ConfigOptions.fragmentPackets.notifier).update(v);
                        },
                      ),
                    ),
                  ),
                ),
                _RangeRow(
                  title: 'Размер кусков, байт',
                  subtitle: 'Меньше — надёжнее, но медленнее. Например, 10-30',
                  option: ConfigOptions.tlsFragmentSize,
                ),
                _RangeRow(
                  title: 'Пауза между кусками, мс',
                  subtitle: 'Например, 2-8. Больше — надёжнее, но медленнее',
                  option: ConfigOptions.tlsFragmentSleep,
                ),
              ],
            ),
          ),
        SettingsSwitchTile(
          title: 'Смешанный регистр имени сайта',
          subtitle:
              'Пишет имя сайта вразнобой: ExAmPlE.com — некоторые фильтры его не узнают. '
              'Только для серверов с TLS через WebSocket или gRPC.',
          value: mixedCase,
          onChanged: ref.read(ConfigOptions.enableTlsMixedSniCase.notifier).update,
        ),
        SettingsSwitchTile(
          title: 'Дополнение пакетов (паддинг)',
          subtitle:
              'Добавляет случайные байты, чтобы размер пакета не выдавал VPN. '
              'Ядро этой версии настройку пока не применяет.',
          value: padding,
          onChanged: ref.read(ConfigOptions.enableTlsPadding.notifier).update,
          divider: padding,
        ),
        if (padding)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _RangeRow(
              title: 'Размер дополнения, байт',
              subtitle: 'Например, 1-1500',
              option: ConfigOptions.tlsPaddingSize,
              divider: false,
            ),
          ),
      ],
    );
  }
}

class _ParamRow extends StatelessWidget {
  const _ParamRow({required this.title, required this.subtitle, required this.child, this.divider = true});

  final String title;
  final String subtitle;
  final Widget child;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: divider ? const Border(bottom: BorderSide(color: RescueColors.line)) : null,
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: RescueColors.text),
                ),
                Text(subtitle, style: RescueText.caption),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Диапазон «от-до» (OptionalRange) в поле ввода: сохраняется по Enter или при уходе из поля;
/// неверное значение не сохраняется, поле подсвечивается.
class _RangeRow extends HookConsumerWidget {
  const _RangeRow({required this.title, required this.subtitle, required this.option, this.divider = true});

  final String title;
  final String subtitle;
  final StateNotifierProvider<PreferencesNotifier<OptionalRange, String>, OptionalRange> option;
  final bool divider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(option);
    final controller = useTextEditingController(text: value.format());
    final focus = useFocusNode();
    final invalid = useState(false);

    void save() {
      final parsed = OptionalRange.tryParse(controller.text.trim());
      final ok = parsed != null && parsed.min != null && (parsed.max == null || parsed.max! >= parsed.min!);
      invalid.value = !ok;
      if (ok) ref.read(option.notifier).update(parsed);
    }

    useEffect(() {
      void onFocus() {
        if (!focus.hasFocus) save();
      }

      focus.addListener(onFocus);
      return () => focus.removeListener(onFocus);
    }, [focus]);

    // Значение сменилось не из поля (сброс и т. п.) — показать его.
    useEffect(() {
      if (!focus.hasFocus && controller.text != value.format()) controller.text = value.format();
      return null;
    }, [value]);

    return _ParamRow(
      title: title,
      subtitle: subtitle,
      divider: divider,
      child: SizedBox(
        width: 120,
        child: TextField(
          controller: controller,
          focusNode: focus,
          onSubmitted: (_) => save(),
          style: RescueText.body,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            isDense: true,
            errorText: invalid.value ? 'например, 10-30' : null,
            errorStyle: const TextStyle(fontSize: 11, color: RescueColors.warn),
          ),
        ),
      ),
    );
  }
}

// ---------- Для опытных ----------

class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection();

  @override
  Widget build(BuildContext context) {
    return RescueCard.deep(
      semanticLabel: 'Для опытных',
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: SectionLabel('Для опытных', color: RescueColors.accent),
          ),
          for (final link in advancedLinks.take(4))
            SettingsLinkTile(
              title: link.title,
              subtitle: link.subtitle,
              onDeep: true,
              onTap: () => openRescueRoute(context, link.routeName),
            ),
          SettingsLinkTile(
            title: 'Все настройки для опытных',
            subtitle: 'Ещё: прочие настройки ядра, о программе',
            onDeep: true,
            divider: false,
            onTap: () => openRescueRoute(context, advancedSettingsRouteName, fallback: const AdvancedSettingsPage()),
          ),
        ],
      ),
    );
  }
}
