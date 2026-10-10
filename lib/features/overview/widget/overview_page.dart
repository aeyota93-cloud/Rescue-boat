import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/features/insights/data/error_groups.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/insights/notifier/insights_settings.dart';
import 'package:hiddify/features/insights/widget/insights_format.dart';
import 'package:hiddify/features/overview/notifier/vpn_status.dart';
import 'package:hiddify/features/overview/widget/vpn_power.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: «Главная» в стиле «Д» (макет docs/redesign/mockup/style-d-dark.html, экран home).
///
/// Сверху жёлтый блок подключения: кнопка питания и статус, выбор подписки и режимы, закладки
/// «Связь | Здоровье» с кольцами. Ниже — ошибки за час, раздельный туннель и подписка.
/// Без бокового меню: каркас (RescueShell) подключается снаружи. Трафика по программам и сайтам
/// здесь нет и не будет (решение пользователя), только факты из ядра и файлов статистики.
class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: RescueColors.panel,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(),
            SizedBox(height: 20),
            ConnectionBlock(),
            SizedBox(height: 20),
            RescueGrid(minItemWidth: 300, spacing: 20, children: [_ErrorsCard(), _TunnelCard(), _SubscriptionCard()]),
          ],
        ),
      ),
    );
  }
}

/// Подпись, когда замеров нет.
const noHealthData = 'Нет данных: замеры идут, пока VPN включён';

/// Переход по маршруту, если приложение с роутером (в тестах страница может жить без него).
void _go(BuildContext context, String location) => GoRouter.maybeOf(context)?.go(location);

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final measure = ref.watch(insightsSettingsProvider.select((s) => s.measurePing));
    return SectionLabel.screen(
      'Главная',
      trailing: Text(measure ? 'замеры раз в минуту' : 'замеры пинга выключены', style: RescueText.caption),
    );
  }
}

// ---------------------------------------------------------------- Жёлтый блок

/// Жёлтый блок подключения: кнопка и статус, сервер и режим, закладки «Связь | Здоровье».
///
/// Широко (≥ 900 внутри блока) — три колонки, как в макете; средне — кнопка с сервером в ряд,
/// закладки ниже; узко — всё столбиком.
class ConnectionBlock extends StatelessWidget {
  const ConnectionBlock({super.key});

  static const _gap = 28.0;

  @override
  Widget build(BuildContext context) {
    const power = _PowerColumn();
    const picker = _PickerColumn();
    const tabs = _SummaryTabs();
    return RescueCard.accent(
      semanticLabel: 'Подключение',
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth >= 900) {
            return const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 230, child: power),
                SizedBox(width: _gap),
                Expanded(flex: 30, child: picker),
                SizedBox(width: _gap),
                Expanded(flex: 36, child: tabs),
              ],
            );
          }
          if (c.maxWidth >= 560) {
            return const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 230, child: power),
                    SizedBox(width: _gap),
                    Expanded(child: picker),
                  ],
                ),
                SizedBox(height: _gap),
                tabs,
              ],
            );
          }
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              power,
              SizedBox(height: _gap),
              picker,
              SizedBox(height: _gap),
              tabs,
            ],
          );
        },
      ),
    );
  }
}

class _PowerColumn extends ConsumerWidget {
  const _PowerColumn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStatusProvider);
    final hasProfile = ref.watch(activeProfileProvider.select((p) => p.valueOrNull != null));
    return Column(
      children: [
        PowerButton(
          state: vpn.power,
          onPressed: vpn.canToggle ? () => toggleVpn(context, ref) : null,
          semanticLabel: vpn.powerLabel,
        ),
        const SizedBox(height: 14),
        Semantics(
          liveRegion: true,
          child: Text(
            vpn.title,
            textAlign: TextAlign.center,
            style: RescueText.statusLight.copyWith(color: RescueColors.onAccent),
          ),
        ),
        const SizedBox(height: 4),
        _StatusLine(vpn: vpn, hasProfile: hasProfile),
      ],
    );
  }
}

/// «01:24:10 · Нидерланды · 48 мс» — время идёт, пока окно открыто. IP не показываем:
/// приложение его не знает (и не спрашивает внешние сервисы).
class _StatusLine extends HookConsumerWidget {
  const _StatusLine({required this.vpn, required this.hasProfile});

  final VpnStatus vpn;
  final bool hasProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final since = vpn.on ? ref.watch(vpnConnectedSinceProvider) : null;
    final tick = useState(0);
    useEffect(() {
      if (since == null) return null;
      final timer = Timer.periodic(const Duration(seconds: 1), (_) => tick.value++);
      return timer.cancel;
    }, [since]);

    final String text;
    if (vpn.on) {
      text = [
        if (since != null) elapsedText(DateTime.now().difference(since)),
        if (vpn.server.isNotEmpty) vpn.server,
        if (vpn.delayMs != null) '${vpn.delayMs} мс',
      ].join(' · ');
    } else if (vpn.busy) {
      text = vpn.server;
    } else if (!hasProfile) {
      text = 'Сначала добавьте подписку';
    } else if (vpn.label == 'Не удалось подключиться') {
      text = 'Нажмите на кнопку, чтобы попробовать снова';
    } else {
      text = 'Нажмите на кнопку, чтобы подключиться';
    }
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      key: const ValueKey('home-status-line'),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, color: RescueColors.onAccentMuted),
    );
  }
}

class _PickerColumn extends StatelessWidget {
  const _PickerColumn();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel('Сервер'),
        SizedBox(height: 10),
        ServerPicker(),
        SizedBox(height: 16),
        SectionLabel('Режим'),
        SizedBox(height: 10),
        _Modes(),
      ],
    );
  }
}

/// Буквы для плитки подписки: «О» для «Основная», «NL» для «NL Amsterdam».
String profileCode(String name) {
  final letter = RegExp(r'[\p{L}\p{N}]', unicode: true);
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty && letter.hasMatch(w.characters.first));
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

/// Адрес подписки без пути и токена: «sub.example.org».
String profileHost(ProfileEntity profile) => switch (profile) {
  RemoteProfileEntity(:final url) => Uri.tryParse(url)?.host ?? '',
  LocalProfileEntity() => '',
};

/// Выбор подписки (профиля Hiddify): выбор делает её активной, ядро переподключается само.
class ServerPicker extends ConsumerWidget {
  const ServerPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesNotifierProvider);
    final vpn = ref.watch(vpnStatusProvider);
    final list = profiles.valueOrNull ?? const <ProfileEntity>[];
    final active = list.where((p) => p.active).firstOrNull;
    final options = [
      for (final p in list)
        ServerOption<String>(
          value: p.id,
          code: profileCode(p.name),
          name: p.name,
          subtitle: () {
            final host = profileHost(p);
            final parts = [
              if (p.active && vpn.connected && vpn.server.isNotEmpty) vpn.server,
              if (host.isNotEmpty) host else if (p is LocalProfileEntity) 'конфиг без ссылки',
            ];
            return parts.isEmpty ? null : parts.join(' · ');
          }(),
          ping: p.active && vpn.on && vpn.delayMs != null ? '${vpn.delayMs} МС' : null,
        ),
    ];
    return ServerSelect<String>(
      options: options,
      value: active?.id,
      placeholder: profiles.isLoading
          ? 'Читаем подписки…'
          : list.isEmpty
          ? 'Подписка не добавлена'
          : 'Подписка не выбрана',
      semanticLabel: 'Подписка',
      onChanged: (id) async {
        if (id == active?.id) return;
        try {
          await ref.read(profilesNotifierProvider.notifier).selectActiveProfile(id);
        } catch (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(const SnackBar(content: Text('Не удалось выбрать подписку')));
        }
      },
      onAdd: () => _go(context, '/servers'),
    );
  }
}

/// Игры и лаунчеры из стандартного списка, которые сейчас в «мимо VPN».
int defaultGamesBypassed(SplitTunnel split) {
  final have = {for (final a in split.bypass.apps) a.toLowerCase()};
  return defaultBypassApps.where((a) => have.contains(a.toLowerCase())).length;
}

/// Режимы — те же переключатели, что в Настройках: способ работы, российские сайты, игры.
class _Modes extends ConsumerWidget {
  const _Modes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final whole = ref.watch(ConfigOptions.serviceMode) == ServiceMode.tun;
    final smart = ref.watch(ConfigOptions.region) == Region.ru;
    final games = defaultGamesBypassed(ref.watch(splitTunnelProvider));
    final gamesOn = games > 0;

    final wholeHint = whole ? 'Все программы и игры' : 'Только браузеры (прокси)';
    final smartHint = smart ? 'Банки и Госуслуги видят домашний IP' : 'Всё через VPN';
    final gamesHint = gamesOn
        ? '$games ${plural(games, 'игра или лаунчер', 'игры и лаунчера', 'игр и лаунчеров')} напрямую'
        : 'Игры тоже через VPN';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ModeChip(
              label: 'Весь компьютер',
              selected: whole,
              hint: wholeHint,
              onChanged: (v) =>
                  ref.read(ConfigOptions.serviceMode.notifier).update(v ? ServiceMode.tun : ServiceMode.systemProxy),
            ),
            ModeChip(
              label: 'Российские сайты напрямую',
              selected: smart,
              hint: smartHint,
              onChanged: (v) => ref.read(ConfigOptions.region.notifier).update(v ? Region.ru : Region.other),
            ),
            ModeChip(
              label: 'Игры мимо VPN',
              selected: gamesOn,
              hint: gamesHint,
              onChanged: (v) {
                final split = ref.read(splitTunnelProvider.notifier);
                v
                    ? split.addAll(SplitTarget.bypass, SplitKind.app, defaultBypassApps)
                    : split.removeEverywhere(SplitKind.app, defaultBypassApps);
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        ExcludeSemantics(
          child: Text(
            [wholeHint, smartHint, gamesHint].join(' · '),
            style: const TextStyle(fontSize: 12, color: RescueColors.onAccentMuted),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Связь | Здоровье

enum _Tab { link, health }

/// Доля дуги кольца: значение относительно «плохо» из формулы оценки.
double _share(num? value, num bad) => value == null ? 0 : (value / bad).clamp(0, 1).toDouble();

class _SummaryTabs extends HookConsumerWidget {
  const _SummaryTabs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = useState(_Tab.link);
    final vpn = ref.watch(vpnStatusProvider);
    final healthValue = ref.watch(healthProvider);
    final health = healthValue.valueOrNull;
    final known = health != null && !health.isEmpty;
    final hourEvents = ref.watch(errorEventsProvider(InsightsPeriod.hour)).valueOrNull;
    final stalls = hourEvents == null ? null : countErrors(hourEvents.where((e) => e.kind == ErrorKind.stall));

    String note() {
      if (health == null) return healthValue.hasError ? 'Не удалось прочитать замеры' : 'Читаем замеры…';
      return noHealthData;
    }

    final List<Widget> rings;
    final String title;
    if (tab.value == _Tab.link) {
      title = [
        if (!vpn.on) 'VPN выключен' else 'VPN включён',
        if (vpn.on && vpn.server.isNotEmpty) vpn.server,
        if (!known) note(),
      ].join(' · ');
      final loss = health?.lossPercent;
      rings = [
        RingStat(
          value: _share(health?.pingMs, 150),
          label: health?.pingMs?.toString() ?? '—',
          title: 'МС ПИНГ',
          caption: 'медиана за сутки',
        ),
        RingStat(
          value: _share(health?.jitterMs, 60),
          label: health?.jitterMs?.toString() ?? '—',
          title: 'МС РАЗБРОС',
          caption: 'джиттер за сутки',
        ),
        RingStat(
          value: _share(loss, 10),
          label: loss == null ? '—' : formatPercentNumber(loss),
          title: '% ПОТЕРЬ',
          caption: 'за сутки',
        ),
        RingStat(
          value: _share(stalls, 10),
          label: stalls?.toString() ?? '—',
          title: 'ЗАМИРАНИЙ',
          caption: 'за час',
          color: (stalls ?? 0) > 0 ? RescueColors.warn : RescueColors.accent,
        ),
      ];
    } else {
      title = known ? 'За 24 часа' : note();
      RingStat ring(HealthMetric? m, String name) => RingStat(
        value: m?.score == null ? 0 : m!.score! / 100,
        label: m?.score?.toString() ?? '—',
        title: name,
        caption: m?.caption ?? 'нет данных',
      );
      rings = [
        ring(health?.overall, 'ОБЩАЯ'),
        ring(health?.ping, 'ПИНГ'),
        ring(health?.stability, 'СТАБИЛЬНОСТЬ'),
        ring(health?.errorsFree, 'БЕЗ ОШИБОК'),
      ];
    }

    return FolderTabs<_Tab>(
      semanticLabel: 'Сводка',
      tabs: [
        FolderTab(
          value: _Tab.link,
          title: 'Связь',
          badge: vpn.on ? 'ВКЛ' : 'ВЫКЛ',
          semanticLabel: 'Связь, VPN ${vpn.on ? 'включён' : 'выключен'}',
        ),
        FolderTab(
          value: _Tab.health,
          title: 'Здоровье',
          badge: health?.overall.score?.toString() ?? '—',
          semanticLabel: 'Здоровье, ${health?.overall.score ?? 'нет данных'}',
        ),
      ],
      value: tab.value,
      onChanged: (t) => tab.value = t,
      inactiveForeground: RescueColors.onAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: RescueText.smallSecondary),
          const SizedBox(height: 16),
          RescueGrid(minItemWidth: 150, runSpacing: 16, children: rings),
        ],
      ),
    );
  }
}

/// Проценты без знака для кольца: «1», «0,4», «0».
String formatPercentNumber(double percent) {
  if (percent <= 0) return '0';
  if (percent < 1) return '0,${(percent * 10).round().clamp(1, 9)}';
  return '${percent.round()}';
}

// ---------------------------------------------------------------- Нижние карточки

class _ErrorsCard extends ConsumerWidget {
  const _ErrorsCard();

  static const _shown = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hour = ref.watch(errorCountProvider(const Duration(hours: 1)));
    final groupsValue = ref.watch(errorGroupsProvider(InsightsPeriod.hour));
    final groups = groupsValue.valueOrNull;

    final List<Widget> rows;
    if (groups != null && groups.isNotEmpty) {
      rows = [
        for (final (i, g) in groups.take(_shown).indexed)
          DeepListTile(
            leading: tileLetter(g.target),
            title: g.target,
            subtitle: groupSubtitle(g),
            trailingText: '${g.count}',
            highlighted: i == 0,
            semanticLabel: '${g.target}, ${groupSubtitle(g)}, ${g.count} ${errorsWord(g.count)}',
          ),
      ];
    } else {
      final text = groups != null
          ? 'За последний час ошибок не было'
          : groupsValue.hasError
          ? 'Не удалось прочитать журнал ошибок'
          : 'Читаем журнал ошибок…';
      rows = [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(text, style: const TextStyle(fontSize: 13, color: RescueColors.subOnDeep)),
        ),
      ];
    }

    return DeepList(
      title: 'Ошибки за час',
      count: '$hour',
      semanticLabel: 'Ошибки за час: $hour',
      actionLabel: 'Все ошибки',
      onAction: () => _go(context, '/errors'),
      children: rows,
    );
  }
}

class _TunnelCard extends ConsumerWidget {
  const _TunnelCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitTunnelProvider);
    int size(SplitList l) => l.apps.length + l.domains.length + l.ips.length;
    return RescueCard(
      semanticLabel: 'Раздельный туннель',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Раздельный туннель'),
          const SizedBox(height: 14),
          StatColumns(
            columns: [
              StatColumn(label: 'МИМО VPN', value: '${size(split.bypass)}'),
              StatColumn(label: 'ЧЕРЕЗ VPN', value: '${size(split.via)}', lineColor: RescueColors.accent),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Списки важнее общих правил и действуют сразу, без переподключения.',
            style: RescueText.smallSecondary,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              style: RescueTheme.deepFilledButton(),
              onPressed: () => _go(context, '/split'),
              child: const Text('Открыть туннель'),
            ),
          ),
        ],
      ),
    );
  }
}

/// «48 ГБ», «4,5 ГБ», «820 МБ».
String sizeText(int bytes) {
  const gb = 1073741824;
  const mb = 1048576;
  if (bytes >= gb) {
    final v = bytes / gb;
    return '${v < 10 ? v.toStringAsFixed(1).replaceAll('.', ',').replaceAll(',0', '') : v.round()} ГБ';
  }
  return '${(bytes / mb).round()} МБ';
}

/// Больше этого — «без ограничения» (как в старой карточке профиля).
const _unlimitedBytes = 10 * 1099511627776;

/// Метка справа от подписи блока: «ДО 9 НОЯБРЯ».
class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.color = RescueColors.text});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
    decoration: BoxDecoration(color: RescueColors.panel, borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: RescueText.microLabel.copyWith(color: color)),
  );
}

class _SubscriptionCard extends ConsumerWidget {
  const _SubscriptionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeProfileProvider);
    final profile = active.valueOrNull;
    final now = DateTime.now();
    final sub = profile is RemoteProfileEntity ? profile.subInfo : null;

    String? tag;
    var tagColor = RescueColors.text;
    if (sub != null) {
      if (sub.isExpired) {
        tag = 'ИСТЕКЛА';
        tagColor = RescueColors.warn;
      } else if (sub.remaining.inDays > 3650) {
        tag = 'БЕЗ СРОКА';
      } else {
        tag = 'ДО ${dayMonthLong(sub.expire)}${sub.expire.year != now.year ? ' ${sub.expire.year}' : ''}'.toUpperCase();
      }
    }

    final children = <Widget>[SectionLabel('Подписка', trailing: tag == null ? null : _Tag(tag, color: tagColor))];
    if (profile == null) {
      children.addAll([
        const SizedBox(height: 12),
        Text(active.isLoading ? 'Читаем подписку…' : 'Подписка не добавлена', style: RescueText.smallSecondary),
      ]);
    } else {
      if (sub != null) {
        final limited = sub.total > 0 && sub.total <= _unlimitedBytes;
        children.addAll([
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              text: '${sizeText(sub.consumption)} ',
              style: RescueText.bigLight,
              children: [
                TextSpan(
                  text: limited ? 'из ${sizeText(sub.total).replaceAll(' ГБ', '')}' : 'без ограничения',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: RescueColors.muted),
                ),
              ],
            ),
          ),
          if (limited) ...[
            const SizedBox(height: 12),
            RescueProgressBar(value: sub.ratio, color: sub.ratio >= 0.9 ? RescueColors.warn : RescueColors.deep),
          ],
        ]);
      }
      final updated = profile.lastUpdate;
      children.addAll([
        const SizedBox(height: 12),
        Text(
          '${profile.name} · обновлена ${sameDay(updated, now) ? 'в ${hhmm(updated)}' : '${dayMonthShort(updated)} в ${hhmm(updated)}'}',
          style: RescueText.caption,
        ),
      ]);
    }
    children.addAll([
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: () => _go(context, '/servers'),
          child: Text(profile == null ? 'Добавить подписку' : 'Подписки и серверы'),
        ),
      ),
    ]);

    return RescueCard(
      semanticLabel: 'Подписка',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}
