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
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/link_parsers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: «Подписки и серверы» (Servers.dc.html) — всё, что умели страницы «Профили» и «Прокси»:
/// добавить по ссылке, обновить, переименовать, удалить, выбрать активную подписку и сервер, проверить пинг.
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
                  child: const Text('Проверить все'),
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
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            const _ServersCard(),
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
        LayoutBuilder(
          builder: (context, constraints) {
            final main = _SubscriptionCard(profile: active);
            const backup = _BackupCard();
            if (constraints.maxWidth < 836) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [main, const SizedBox(height: 16), backup],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: main),
                const SizedBox(width: 16),
                const Expanded(child: backup),
              ],
            );
          },
        ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 16),
          RescueCard(
            semanticLabel: 'Другие подписки',
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Другие подписки', style: RescueText.cardTitle),
                const SizedBox(height: 4),
                const Text(
                  'Работает только активная. Сделайте другую активной, чтобы перейти на её серверы.',
                  style: RescueText.caption,
                ),
                const SizedBox(height: 8),
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
    return RescueCard(
      semanticLabel: 'Подписки',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Подписок пока нет', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Вставьте ссылку на подписку, которую дал владелец сервера, — серверы появятся здесь.',
            style: TextStyle(fontSize: 14, height: 1.5, color: RescueColors.textTertiary),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => showAddSubscription(context, ref), child: const Text('+ Добавить подписку')),
        ],
      ),
    );
  }
}

class _SubscriptionCard extends HookConsumerWidget {
  const _SubscriptionCard({required this.profile});

  final ProfileEntity profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final remote = profile is RemoteProfileEntity ? profile as RemoteProfileEntity : null;
    final info = remote?.subInfo;
    final updating = remote != null && ref.watch(updateProfileNotifierProvider(profile.id)).isLoading;

    final tiles = <Widget>[
      if (info != null)
        if (isUnlimitedTraffic(info))
          StatTile(
            label: 'Израсходовано',
            value: '${formatGb(info.consumption)} ГБ',
            caption: 'без ограничения',
            inset: true,
          )
        else
          StatTile(
            label: 'Израсходовано',
            value: '${formatGb(info.consumption)} из ${formatGb(info.total)} ГБ',
            progress: info.ratio,
            progressColor: info.ratio > 0.9
                ? RescueColors.poor
                : info.ratio > 0.75
                ? RescueColors.fair
                : RescueColors.good,
            inset: true,
          ),
      if (info != null)
        isUnlimitedTime(info)
            ? const StatTile(label: 'Действует до', value: 'бессрочно', inset: true)
            : StatTile(
                label: 'Действует до',
                value: ruDate(info.expire.toLocal()),
                caption: daysLeftLabel(info.expire, now),
                valueColor: info.isExpired ? RescueColors.poor : RescueColors.text,
                inset: true,
              ),
      StatTile(
        label: 'Обновлена',
        value: updatedLabel(profile.lastUpdate, now),
        caption: autoUpdateLabel(profile),
        inset: true,
      ),
    ];

    return RescueCard(
      semanticLabel: 'Подписка «${profile.name}»',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        profile.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: RescueColors.text),
                      ),
                    ),
                    if (profile.active) const RescueBadge(label: 'активна', kind: RescueBadgeKind.success),
                  ],
                ),
              ),
              _ProfileMenu(profile: profile),
            ],
          ),
          const SizedBox(height: 14),
          RescueGrid(minItemWidth: 160, children: tiles),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!profile.active)
                FilledButton(
                  onPressed: () => ref.read(profilesNotifierProvider.notifier).selectActiveProfile(profile.id),
                  child: const Text('Сделать активной'),
                ),
              if (remote != null)
                OutlinedButton(
                  onPressed: updating
                      ? null
                      : () => ref.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(remote),
                  child: Text(updating ? 'Обновляется…' : 'Обновить сейчас'),
                ),
              OutlinedButton(onPressed: () => _rename(context, ref, profile), child: const Text('Переименовать')),
              OutlinedButton(
                onPressed: () => _delete(context, ref, profile),
                style: RescueTheme.dangerOutlinedButton(),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ],
      ),
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
      if (info != null && !isUnlimitedTime(info))
        info.isExpired ? 'истекла' : 'до ${ruDate(info.expire.toLocal())}',
      'обновлена ${updatedLabel(profile.lastUpdate, now)}',
    ].join(' · ');
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: divider ? const Border(bottom: BorderSide(color: RescueColors.rowLine)) : null,
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
                Text(profile.name, style: RescueText.bodyStrong),
                Text(facts, style: RescueText.caption),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
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
  const _ProfileMenu({required this.profile, this.withRename = false});

  final ProfileEntity profile;
  final bool withRename;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = profile is RemoteProfileEntity ? profile as RemoteProfileEntity : null;
    return PopupMenuButton<void>(
      tooltip: 'Ещё',
      icon: const Icon(Icons.more_horiz_rounded),
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
              if (link.isNotEmpty) await ref.read(dialogNotifierProvider.notifier).showQrCode(link, message: remote.name);
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

class _BackupCard extends ConsumerWidget {
  const _BackupCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RescueCard.dashed(
      semanticLabel: 'Запасной вариант',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Запасной', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          const Text(
            'Если основной сервер не отвечает, программа сама переключится на запасной.',
            style: TextStyle(fontSize: 14, height: 1.5, color: RescueColors.textTertiary),
          ),
          const SizedBox(height: 10),
          const Text('Пока не добавлен.', style: RescueText.smallSecondary),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => showAddSubscription(context, ref), child: const Text('Добавить запасной')),
        ],
      ),
    );
  }
}

// ---------- серверы ----------

class _ServersCard extends ConsumerWidget {
  const _ServersCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxies = ref.watch(proxiesOverviewNotifierProvider);
    final sortBy = ref.watch(proxiesSortNotifierProvider);
    return RescueCard(
      semanticLabel: 'Серверы',
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Semantics(header: true, child: const Text('Серверы в подписке', style: RescueText.cardTitle)),
              Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Нажмите строку, чтобы выбрать', style: RescueText.smallSecondary),
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
            ],
          ),
          const SizedBox(height: 8),
          switch (proxies) {
            AsyncData(value: final group?) when group.items.isNotEmpty => _ServersTable(group: group),
            AsyncData() => const _Note('В подписке нет серверов.'),
            AsyncError(error: ServiceNotRunning()) => const _Note(
              'Список серверов и пинг видны, когда VPN подключён.',
            ),
            AsyncError() => const _Note('Не удалось получить список серверов от ядра.'),
            _ => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        ],
      ),
    );
  }

  static String _sortTitle(ProxiesSort s) => switch (s) {
    ProxiesSort.unsorted => 'Как в подписке',
    ProxiesSort.name => 'По имени',
    ProxiesSort.delay => 'По пингу',
    ProxiesSort.usage => 'По расходу',
  };
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(text, style: RescueText.smallSecondary));
}

class _ServersTable extends ConsumerWidget {
  const _ServersTable({required this.group});

  final OutboundGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider).valueOrNull;
    return RescueTable(
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
        for (final item in group.items)
          () {
            final selected = group.selected == item.tag;
            final name = item.tagDisplay.isNotEmpty ? item.tagDisplay : item.tag;
            final proto = protocolName(item.type);
            final delay = item.urlTestDelay;
            final overall = selected && health != null && !health.isEmpty ? health.overall : null;
            final sub = _subtitle(item);
            return RescueTableRow(
              selected: selected,
              onTap: () => ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(group.tag, item.tag),
              semanticLabel: [
                name,
                proto,
                'пинг ${pingLabel(delay)}',
                if (overall?.score case final score?) 'здоровье $score',
                if (selected) 'выбран',
              ].join(', '),
              cells: [
                _Radio(selected: selected),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: RescueColors.text,
                        fontFamilyFallback: [FontFamily.emoji],
                      ),
                    ),
                    if (sub.isNotEmpty) Text(sub, style: RescueText.caption),
                  ],
                ),
                Text(proto, style: const TextStyle(fontSize: 13, color: RescueColors.textTertiary)),
                Row(
                  children: [
                    Expanded(
                      child: RescueProgressBar(
                        value: pingFraction(delay),
                        color: _pingColor(delay),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 76,
                      child: Text(
                        pingLabel(delay),
                        style: RescueText.bodyStrong.copyWith(
                          color: pingTimedOut(delay) ? RescueColors.poor : RescueColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
                if (overall != null)
                  Row(
                    children: [
                      Expanded(child: ScoreBar(good: overall.good, fair: overall.fair, poor: overall.poor, gap: 2)),
                      const SizedBox(width: 8),
                      SizedBox(width: 28, child: Text('${overall.score}', style: RescueText.bodyStrong)),
                    ],
                  )
                else
                  const Text('—', style: TextStyle(color: RescueColors.textSecondary)),
              ],
            );
          }(),
      ],
    );
  }

  static String _subtitle(OutboundInfo item) {
    final current = item.groupSelectedTagDisplay.trim();
    if (item.type.toLowerCase() == 'urltest') {
      return current.isEmpty ? 'сам берёт самый быстрый из рабочих' : 'сам берёт самый быстрый · сейчас $current';
    }
    if (item.isGroup) return current.isEmpty ? 'группа серверов' : 'группа · сейчас $current';
    return item.host;
  }

  static Color _pingColor(int delay) {
    if (delay <= 0) return RescueColors.track;
    if (pingTimedOut(delay) || delay >= 300) return RescueColors.poor;
    if (delay >= 150) return RescueColors.fair;
    return RescueColors.good;
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
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
