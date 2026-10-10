import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/common/rescue_page_header.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/servers/data/rename_profile.dart';
import 'package:hiddify/features/servers/model/servers_format.dart';
import 'package:hiddify/features/split_tunnel/model/tunnel_rows.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/link_parsers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: «Подписки и серверы» в стиле «Д» — всё, что умели страницы «Профили» и «Прокси»:
/// добавить по ссылке, обновить, переименовать, удалить, выбрать активную подписку и сервер, проверить пинг.
///
/// Активная подписка — жёлтый блок с кольцами (расход, срок, автообновление — только то, что
/// прислал сервер подписки), ниже — карточки серверов с пингом и пунктирная карточка «Запасной».
class ServersPage extends HookConsumerWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesNotifierProvider);
    final proxies = ref.watch(proxiesOverviewNotifierProvider);
    final adding = ref.watch(addProfileNotifierProvider).isLoading;
    final group = proxies.valueOrNull;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RescuePageHeader(
              title: 'Подписки и серверы',
              actions: [
                OutlinedButton(
                  onPressed: group == null
                      ? null
                      : () => ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(group.tag),
                  child: const Text('Проверить пинг'),
                ),
                FilledButton(
                  onPressed: adding ? null : () => showAddSubscription(context, ref),
                  child: Text(adding ? 'Добавляется…' : '+ Добавить подписку'),
                ),
                PopupMenuButton<void>(
                  tooltip: 'Ещё',
                  icon: const Icon(Icons.more_horiz_rounded),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      onTap: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
                      child: const Text('Обновить все подписки'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            switch (profiles) {
              AsyncData(:final value) => _Subscriptions(profiles: value),
              AsyncError() => const RescueCard(
                child: Text('Не удалось прочитать список подписок.', style: RescueText.smallSecondary),
              ),
              _ => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
            const SizedBox(height: 24),
            const _ServersSection(),
          ],
        ),
      ),
    );
  }
}

/// Добавление подписки: ссылка (можно из буфера) или «другие способы» — старое окно Hiddify
/// (QR-код, вручную, из файла).
Future<void> showAddSubscription(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<_AddResult>(context: context, builder: (_) => const _AddSubscriptionDialog());
  switch (result) {
    case _AddLink(:final text):
      await ref.read(addProfileNotifierProvider.notifier).addClipboard(text);
    case _AddOther():
      await ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();
    case null:
      break;
  }
}

// ---------- подписки ----------

class _Subscriptions extends StatelessWidget {
  const _Subscriptions({required this.profiles});

  final List<ProfileEntity> profiles;

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty) return const _EmptySubscriptions();
    final active = profiles.firstWhere((p) => p.active, orElse: () => profiles.first);
    final others = profiles.where((p) => p.id != active.id).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubscriptionCard(profile: active),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 20),
          RescueCard(
            semanticLabel: 'Другие подписки',
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel('Другие подписки', count: '${others.length}'),
                const SizedBox(height: 4),
                const Text(
                  'Работает только активная. Сделайте другую активной, чтобы перейти на её серверы.',
                  style: RescueText.caption,
                ),
                const SizedBox(height: 4),
                for (final (i, p) in others.indexed) _OtherSubscriptionRow(profile: p, divider: i < others.length - 1),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptySubscriptions extends ConsumerWidget {
  const _EmptySubscriptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RescueCard.accent(
      semanticLabel: 'Подписки',
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Подписок пока нет', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w300)),
          const SizedBox(height: 6),
          const Text(
            'Вставьте ссылку на подписку, которую дал владелец сервера, — серверы появятся здесь.',
            style: TextStyle(fontSize: 13, color: RescueColors.onAccentMuted),
          ),
          const SizedBox(height: 14),
          FilledButton(
            style: RescueTheme.deepFilledButton(),
            onPressed: () => showAddSubscription(context, ref),
            child: const Text('+ Добавить подписку'),
          ),
        ],
      ),
    );
  }
}

/// Метка «АКТИВНА» на жёлтом: тёмная плашка с жёлтым текстом (10 / 700 / 0.12em).
class _ActiveTag extends StatelessWidget {
  const _ActiveTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: RescueColors.deep, borderRadius: BorderRadius.circular(6)),
    child: const Text(
      'АКТИВНА',
      semanticsLabel: 'активна',
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: RescueColors.accent),
    ),
  );
}

/// Активная подписка — жёлтый блок: метка, название, адрес и даты; кольца расхода, срока и
/// автообновления (только то, что прислал сервер подписки); кнопки.
class _SubscriptionCard extends HookConsumerWidget {
  const _SubscriptionCard({required this.profile});

  final ProfileEntity profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final remote = profile is RemoteProfileEntity ? profile as RemoteProfileEntity : null;
    final info = remote?.subInfo;
    final updating = remote != null && ref.watch(updateProfileNotifierProvider(profile.id)).isLoading;

    final facts = [
      if (remote != null) subscriptionHost(remote.url) ?? 'по ссылке' else 'конфиг без ссылки',
      if (info != null && !isUnlimitedTime(info)) info.isExpired ? 'истекла' : 'до ${ruDate(info.expire.toLocal())}',
      'обновлена ${updatedLabel(profile.lastUpdate, now)}',
    ].join(' · ');

    final rings = <Widget>[
      if (info != null) _trafficRing(info),
      if (info != null) _timeRing(info, now),
      if (remote != null) _updateRing(remote, now),
    ];

    return RescueCard.accent(
      semanticLabel: 'Подписка «${profile.name}»',
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 28),
      child: Wrap(
        spacing: 24,
        runSpacing: 20,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (profile.active) ...[const _ActiveTag(), const SizedBox(height: 6)],
                Row(
                  children: [
                    Flexible(
                      child: Semantics(
                        header: true,
                        child: Text(
                          profile.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w300,
                            fontFamilyFallback: [FontFamily.emoji],
                          ),
                        ),
                      ),
                    ),
                    _ProfileMenu(profile: profile, color: RescueColors.onAccent),
                  ],
                ),
                Text(facts, style: const TextStyle(fontSize: 13, color: RescueColors.onAccentMuted)),
              ],
            ),
          ),
          if (rings.isNotEmpty) Wrap(spacing: 22, runSpacing: 12, children: rings),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!profile.active)
                FilledButton(
                  style: RescueTheme.deepFilledButton(),
                  onPressed: () => ref.read(profilesNotifierProvider.notifier).selectActiveProfile(profile.id),
                  child: const Text('Сделать активной'),
                ),
              if (remote != null)
                FilledButton(
                  style: RescueTheme.deepFilledButton(),
                  onPressed: updating
                      ? null
                      : () => ref.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(remote),
                  child: Text(updating ? 'Обновляется…' : 'Обновить'),
                ),
              OutlinedButton(
                style: RescueTheme.outlinedOnAccentButton(),
                onPressed: () => _rename(context, ref, profile),
                child: const Text('Переименовать'),
              ),
              OutlinedButton(
                style: RescueTheme.dangerOnAccentButton(),
                onPressed: () => _delete(context, ref, profile),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _trafficRing(SubscriptionInfo info) {
    final used = formatGb(info.consumption);
    if (isUnlimitedTraffic(info)) {
      return RingStat.onAccent(
        value: 0,
        label: used,
        title: 'ГБ\nБЕЗ ЛИМИТА',
        semanticLabel: 'Израсходовано $used ГБ, без ограничения',
      );
    }
    final total = formatGb(info.total);
    return RingStat.onAccent(
      value: info.ratio,
      label: used,
      title: 'ГБ\nИЗ $total',
      semanticLabel: 'Израсходовано $used из $total ГБ',
    );
  }

  /// Кольцо срока: заполнение — сколько осталось из 30 дней (сервер присылает только дату окончания).
  static Widget _timeRing(SubscriptionInfo info, DateTime now) {
    if (isUnlimitedTime(info)) {
      return const RingStat.onAccent(value: 1, label: '∞', title: 'СРОК\nБЕССРОЧНО', semanticLabel: 'Бессрочно');
    }
    final until = ruDate(info.expire.toLocal());
    if (!info.expire.isAfter(now)) {
      return RingStat.onAccent(
        value: 0,
        label: '0',
        title: 'СРОК\nИСТЁК',
        semanticLabel: 'Подписка истекла $until',
      );
    }
    final days = info.expire.difference(now).inDays;
    return RingStat.onAccent(
      value: (days / 30).clamp(0.02, 1.0),
      label: days == 0 ? '<1' : '$days',
      title: '${pluralRu(days == 0 ? 1 : days, 'ДЕНЬ', 'ДНЯ', 'ДНЕЙ')}\nОСТАЛОСЬ',
      semanticLabel: 'Действует до $until, ${daysLeftLabel(info.expire, now)}',
    );
  }

  /// Кольцо автообновления: число — раз во сколько часов, заполнение — сколько прошло с прошлого.
  static Widget _updateRing(RemoteProfileEntity profile, DateTime now) {
    final hours = profile.options?.updateInterval.inHours ?? 0;
    final auto = hours > 0 && !(profile.userOverride?.isAutoUpdateDisable ?? false);
    final updated = updatedLabel(profile.lastUpdate, now);
    if (!auto) {
      return RingStat.onAccent(
        value: 0,
        label: '—',
        title: 'ОБНОВЛЕНИЕ\nВРУЧНУЮ',
        semanticLabel: 'Обновляется вручную, обновлена $updated',
      );
    }
    final passed = now.difference(profile.lastUpdate).inMinutes / (hours * 60);
    return RingStat.onAccent(
      value: passed.clamp(0.02, 1.0),
      label: '$hoursч',
      title: 'ОБНОВЛЕНИЕ\nСАМО',
      semanticLabel: 'Обновляется ${autoUpdateLabel(profile)}, обновлена $updated',
    );
  }
}

class _OtherSubscriptionRow extends HookConsumerWidget {
  const _OtherSubscriptionRow({required this.profile, required this.divider});

  final ProfileEntity profile;
  final bool divider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final remote = profile is RemoteProfileEntity ? profile as RemoteProfileEntity : null;
    final info = remote?.subInfo;
    final updating = remote != null && ref.watch(updateProfileNotifierProvider(profile.id)).isLoading;
    final facts = [
      if (info != null)
        isUnlimitedTraffic(info)
            ? '${formatGb(info.consumption)} ГБ, без ограничения'
            : '${formatGb(info.consumption)} из ${formatGb(info.total)} ГБ',
      if (info != null && !isUnlimitedTime(info)) info.isExpired ? 'истекла' : 'до ${ruDate(info.expire.toLocal())}',
      'обновлена ${updatedLabel(profile.lastUpdate, now)}',
    ].join(' · ');
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(vertical: 10),
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
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(profile.name, style: RescueText.rowTitle),
                Text(facts, style: RescueText.caption),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: () => ref.read(profilesNotifierProvider.notifier).selectActiveProfile(profile.id),
                child: const Text('Сделать активной'),
              ),
              if (remote != null)
                OutlinedButton(
                  onPressed: updating
                      ? null
                      : () => ref.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(remote),
                  child: Text(updating ? 'Обновляется…' : 'Обновить'),
                ),
              OutlinedButton(
                onPressed: () => _delete(context, ref, profile),
                style: RescueTheme.dangerOutlinedButton(),
                child: const Text('Удалить'),
              ),
              _ProfileMenu(profile: profile, withRename: true),
            ],
          ),
        ],
      ),
    );
  }
}

/// «⋯» у подписки: поделиться, QR-код, конфиг, подробная правка (то, что было в меню профиля Hiddify).
class _ProfileMenu extends ConsumerWidget {
  const _ProfileMenu({required this.profile, this.withRename = false, this.color});

  final ProfileEntity profile;
  final bool withRename;

  /// Цвет значка «⋯»; null — из темы (на жёлтом блоке — тёмный).
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = profile is RemoteProfileEntity ? profile as RemoteProfileEntity : null;
    return PopupMenuButton<void>(
      tooltip: 'Ещё',
      icon: Icon(Icons.more_horiz_rounded, color: color),
      itemBuilder: (_) => [
        if (withRename) PopupMenuItem(onTap: () => _rename(context, ref, profile), child: const Text('Переименовать')),
        if (remote != null) ...[
          PopupMenuItem(
            onTap: () async {
              final link = LinkParser.generateSubShareLink(remote.url, remote.name);
              if (link.isEmpty) return;
              await Clipboard.setData(ClipboardData(text: link));
              if (context.mounted) _snack(context, 'Ссылка скопирована');
            },
            child: const Text('Скопировать ссылку'),
          ),
          PopupMenuItem(
            onTap: () async {
              final link = LinkParser.generateSubShareLink(remote.url, remote.name);
              if (link.isEmpty) return;
              await ref.read(dialogNotifierProvider.notifier).showQrCode(link, message: remote.name);
            },
            child: const Text('Показать QR-код'),
          ),
        ],
        PopupMenuItem(
          onTap: () => ref.read(profilesNotifierProvider.notifier).exportConfigToClipboard(profile),
          child: const Text('Скопировать конфиг (JSON)'),
        ),
        PopupMenuItem(
          onTap: () {
            try {
              context.goNamed('profileDetails', pathParameters: {'id': profile.id});
            } catch (_) {
              _snack(context, 'Подробная правка сейчас недоступна');
            }
          },
          child: const Text('Изменить подробно'),
        ),
      ],
    );
  }
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Future<void> _rename(BuildContext context, WidgetRef ref, ProfileEntity profile) async {
  final controller = TextEditingController(text: profile.name);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Переименовать подписку'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Название'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Сохранить')),
      ],
    ),
  );
  controller.dispose();
  if (name == null || name.trim().isEmpty || name.trim() == profile.name) return;
  final repo = await ref.read(profileRepositoryProvider.future);
  final error = await renameProfile(repo, profile, name);
  if (error != null && context.mounted) _snack(context, error);
}

Future<void> _delete(BuildContext context, WidgetRef ref, ProfileEntity profile) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Удалить подписку «${profile.name}»?'),
      content: const Text('Её серверы пропадут из списка. Ссылку можно будет добавить снова.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, true),
          style: RescueTheme.dangerOutlinedButton(),
          child: const Text('Удалить'),
        ),
      ],
    ),
  );
  if (ok ?? false) await ref.read(profilesNotifierProvider.notifier).deleteProfile(profile);
}

/// Честная заглушка «Запасной»: автопереключения пока нет.
class _BackupCard extends ConsumerWidget {
  const _BackupCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RescueCard.dashed(
      semanticLabel: 'Запасной вариант',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 154),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Запасной', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Автоматическое переключение на запасной сервер появится в следующей версии.',
              style: RescueText.smallSecondary,
            ),
            const SizedBox(height: 6),
            const Text('Пока запасной можно добавить второй подпиской и выбрать вручную.', style: RescueText.caption),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => showAddSubscription(context, ref), child: const Text('Добавить подписку')),
          ],
        ),
      ),
    );
  }
}

// ---------- серверы ----------

class _ServersSection extends ConsumerWidget {
  const _ServersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxies = ref.watch(proxiesOverviewNotifierProvider);
    final sortBy = ref.watch(proxiesSortNotifierProvider);
    final group = proxies.valueOrNull;
    final count = group?.items.length;

    final note = switch (proxies) {
      AsyncData(value: final g?) when g.items.isNotEmpty => null,
      AsyncData() => 'В подписке нет серверов.',
      AsyncError(error: ServiceNotRunning()) => 'Список серверов и пинг видны, когда VPN подключён.',
      AsyncError() => 'Не удалось получить список серверов от ядра.',
      _ => null,
    };

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Серверы',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            'Серверы',
            count: count == null || count == 0 ? null : '$count',
            trailing: Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Нажмите карточку, чтобы выбрать', style: RescueText.caption),
                PopupMenuButton<ProxiesSort>(
                  tooltip: 'Порядок',
                  initialValue: sortBy,
                  onSelected: ref.read(proxiesSortNotifierProvider.notifier).update,
                  icon: const Icon(Icons.sort_rounded),
                  itemBuilder: (_) => [
                    for (final s in ProxiesSort.values) PopupMenuItem(value: s, child: Text(_sortTitle(s))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (note != null) ...[Text(note, style: RescueText.smallSecondary), const SizedBox(height: 12)],
          if (proxies.isLoading && group == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          _FillGrid(
            children: [
              if (group != null) ..._cards(ref, group),
              const _BackupCard(),
            ],
          ),
        ],
      ),
    );
  }

  static List<Widget> _cards(WidgetRef ref, OutboundGroup group) {
    final health = ref.watch(healthProvider).valueOrNull;
    return [
      for (final item in group.items)
        _ServerCard(
          item: item,
          selected: group.selected == item.tag,
          health: group.selected == item.tag && health != null && !health.isEmpty ? health.overall.score : null,
          onTap: () => ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(group.tag, item.tag),
        ),
    ];
  }

  static String _sortTitle(ProxiesSort s) => switch (s) {
    ProxiesSort.unsorted => 'Как в подписке',
    ProxiesSort.name => 'По имени',
    ProxiesSort.delay => 'По пингу',
    ProxiesSort.usage => 'По расходу',
  };
}

/// Сетка карточек как `repeat(auto-fill, minmax(240px, 1fr))`: колонок столько, сколько влезает,
/// карточки не растягиваются на всю ширину, если их мало.
class _FillGrid extends StatelessWidget {
  const _FillGrid({required this.children});

  static const _min = 240.0;
  static const _gap = 16.0;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = ((width + _gap) / (_min + _gap)).floor().clamp(1, 99);
        final itemWidth = ((width - _gap * (columns - 1)) / columns).floorToDouble();
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [for (final c in children) SizedBox(width: itemWidth, child: c)],
        );
      },
    );
  }
}

/// Карточка сервера: плитка с кодом страны, название, протокол, полоска отклика и пинг.
/// Выбранный — тёмная (deep) с жёлтым названием; остальные — card.
class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.item, required this.selected, required this.onTap, this.health});

  final OutboundInfo item;
  final bool selected;
  final VoidCallback onTap;

  /// Общая оценка здоровья за сутки — только у выбранного сервера.
  final int? health;

  @override
  Widget build(BuildContext context) {
    final name = item.tagDisplay.isNotEmpty ? item.tagDisplay : item.tag;
    final proto = switch (item.type.toLowerCase()) {
      'urltest' => 'Автовыбор',
      _ when item.isGroup => 'Группа',
      _ => protocolName(item.type),
    };
    final delay = item.urlTestDelay;
    final sub = _subtitle(item);
    final timedOut = pingTimedOut(delay);
    final health = this.health;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(28));
    final subColor = selected ? RescueColors.subOnDeep : RescueColors.muted;
    final fg = selected ? RescueColors.textOnDeep : RescueColors.text;

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: [
        name,
        proto,
        'пинг ${pingLabel(delay)}',
        if (health != null) 'здоровье за сутки $health',
        if (selected) 'выбран',
      ].join(', '),
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? RescueColors.deep : RescueColors.card,
          shape: shape,
          child: InkWell(
            onTap: onTap,
            customBorder: shape,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 190),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? RescueColors.line : RescueColors.panel,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        serverCode(name),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: selected ? RescueColors.accent : RescueColors.text,
                        fontFamilyFallback: const [FontFamily.emoji],
                      ),
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: subColor),
                      ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: selected ? RescueColors.off : RescueColors.line2),
                      ),
                      child: Text(
                        proto.toUpperCase(),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: fg),
                      ),
                    ),
                    const SizedBox(height: 16),
                    RescueProgressBar(
                      value: timedOut ? 1 : pingSpeedFraction(delay),
                      color: timedOut ? RescueColors.warn : RescueColors.accent,
                      height: 3,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            pingLabel(delay).toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: timedOut ? RescueColors.warn : fg,
                            ),
                          ),
                        ),
                        if (health != null) ...[
                          Text(
                            'ЗДОРОВЬЕ',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: subColor),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$health',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: RescueColors.accent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _subtitle(OutboundInfo item) {
    final current = item.groupSelectedTagDisplay.trim();
    if (item.type.toLowerCase() == 'urltest') {
      return current.isEmpty ? 'сам берёт самый быстрый из рабочих' : 'самый быстрый · сейчас $current';
    }
    if (item.isGroup) return current.isEmpty ? 'группа серверов' : 'группа · сейчас $current';
    return item.host;
  }
}

// ---------- окно добавления ----------

sealed class _AddResult {
  const _AddResult();
}

class _AddLink extends _AddResult {
  const _AddLink(this.text);

  final String text;
}

class _AddOther extends _AddResult {
  const _AddOther();
}

class _AddSubscriptionDialog extends HookWidget {
  const _AddSubscriptionDialog();

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController();
    final text = useValueListenable(controller).text.trim();
    return AlertDialog(
      title: const Text('Добавить подписку'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ссылка на подписку (https://…) или конфиг (vless://…, vmess://…), который дал владелец сервера.',
              style: RescueText.smallSecondary,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(hintText: 'https://…'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    final clip = data?.text?.trim() ?? '';
                    if (clip.isNotEmpty) controller.text = clip;
                  },
                  child: const Text('Вставить из буфера'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, const _AddOther()),
                  child: const Text('Другие способы…'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: text.isEmpty ? null : () => Navigator.pop(context, _AddLink(text)),
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}
