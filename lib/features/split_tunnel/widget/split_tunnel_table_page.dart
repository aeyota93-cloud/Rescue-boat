import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/common/pinned_scroll.dart';
import 'package:hiddify/features/common/rescue_page_header.dart';
import 'package:hiddify/features/compare/model/compare_target.dart';
import 'package:hiddify/features/compare/widget/compare_paths_dialog.dart';
import 'package:hiddify/features/insights/model/insights_models.dart';
import 'package:hiddify/features/insights/notifier/insights_notifiers.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/split_tunnel/model/tunnel_rows.dart';
import 'package:hiddify/features/split_tunnel/notifier/live_connections_notifier.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hiddify/features/split_tunnel/widget/tunnel_dialogs.dart';
import 'package:hiddify/features/split_tunnel/widget/tunnel_groups_view.dart';
import 'package:hiddify/features/split_tunnel/widget/tunnel_live_view.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Вкладки экрана.
enum _View { live, groups }

/// Шлюпка: «Раздельный туннель» (docs/redesign/tunnel-v3.md). Две вкладки:
/// «Сейчас в сети» — что идёт прямо сейчас, через что и почему ([TunnelLiveView]);
/// «Группы» — карточки групп с путём для всех записей сразу и записи по одной ([TunnelGroupsView]).
/// Изменения действуют сразу, без переподключения.
///
/// Если области раздела хватает ([pinnedMinWidth] × [pinnedMinHeight]), шапка, вкладки и поиск
/// закреплены, а списки прокручиваются внутри; меньше — прокручивается вся страница.
class SplitTunnelTablePage extends HookConsumerWidget {
  const SplitTunnelTablePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitTunnelProvider);
    // Соединения опрашиваем, только пока страница видна (скрытая ветка навигации — TickerMode выключен).
    final visible = TickerMode.of(context);
    final connections = visible ? ref.watch(liveConnectionsProvider).valueOrNull : null;
    final errors = ref.watch(errorGroupsProvider(InsightsPeriod.day)).valueOrNull ?? const <ErrorGroup>[];
    final titles = visible ? ref.watch(runningTitlesProvider).valueOrNull ?? const {} : const <String, String>{};
    final view = useState(_View.live);
    final search = useTextEditingController();
    final query = useState('');
    final openGroup = useState<String?>(null);

    final data = buildTunnelRows(split, connections, errors);
    final listed = data.entries.where((e) => e.target != null || e.group != null).toList();

    void openGroupTab(String name) {
      view.value = _View.groups;
      openGroup.value = name;
      search.clear();
      query.value = '';
    }

    String? addGroup() => view.value == _View.groups && (openGroup.value?.isNotEmpty ?? false) ? openGroup.value : null;

    final header = RescuePageHeader(
      title: 'Туннелирование',
      actions: [
        OutlinedButton(
          onPressed: () => showNewGroupDialog(context, entries: listed, titles: titles),
          child: const Text('Новая группа'),
        ),
        OutlinedButton(
          onPressed: () => showAddDialog(context, tab: AddTab.running, group: addGroup()),
          child: const Text('Из запущенных'),
        ),
        FilledButton(
          onPressed: () => showAddDialog(context, group: addGroup()),
          child: const Text('+ Добавить'),
        ),
        PopupMenuButton<void>(
          tooltip: 'Ещё',
          icon: const Icon(Icons.more_horiz_rounded),
          itemBuilder: (_) => [
            PopupMenuItem(
              onTap: () => showComparePathsDialog(context, const CompareSubject.ask()),
              child: const Text('Сравнить пути…'),
            ),
            PopupMenuItem(onTap: () => _confirmReset(context, ref), child: const Text('Вернуть списки по умолчанию')),
          ],
        ),
      ],
    );
    final open = connections?.where((c) => !c.closed).length;
    // На узком окне «В сети»: две вкладки крупным шрифтом иначе не помещаются.
    Widget tabs(bool narrow) => FolderTabs<_View>(
      semanticLabel: 'Вид',
      tabs: [
        FolderTab(
          value: _View.live,
          title: narrow ? 'В сети' : 'Сейчас в сети',
          semanticLabel: 'Сейчас в сети',
          badge: open == null ? null : '$open',
        ),
        FolderTab(value: _View.groups, title: 'Группы', badge: '${split.groups.length}'),
      ],
      value: view.value,
      onChanged: (v) => view.value = v,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: _SearchRow(
        controller: search,
        onChanged: (v) => query.value = v.trim(),
        hint: switch (view.value) {
          _View.live => 'Что идёт прямо сейчас: группа, реальный сервер и почему',
          _View.groups => 'Путь у группы — всем её записям сразу; у записи — только ей',
        },
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final pinned = isPinnedLayout(constraints);
          final body = switch (view.value) {
            _View.live => TunnelLiveView(
              connections: connections,
              titles: titles,
              query: query.value,
              pinned: pinned,
              onOpenGroup: openGroupTab,
              onShowGroups: () => view.value = _View.groups,
            ),
            _View.groups => TunnelGroupsView(
              entries: data.entries,
              titles: titles,
              query: query.value,
              pinned: pinned,
              openGroup: openGroup,
            ),
          };
          final children = [
            header,
            const SizedBox(height: 20),
            tabs(constraints.maxWidth < 560),
            const SizedBox(height: 20),
          ];
          if (pinned) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...children,
                  Expanded(child: body),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...children, body]),
          );
        },
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Вернуть списки по умолчанию?'),
        content: const Text('Оба списка и группы очистятся, в «Мимо VPN» вернутся игры и лаунчеры.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Вернуть')),
        ],
      ),
    );
    if (ok ?? false) ref.read(splitTunnelProvider.notifier).resetToDefaults();
  }
}

/// Поиск (таблетка цвета panel, высота 48) и подсказка к вкладке справа.
class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.controller, required this.onChanged, required this.hint});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    const pill = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(999)), borderSide: BorderSide.none);
    final field = TextField(
      controller: controller,
      onChanged: onChanged,
      style: RescueText.body,
      decoration: const InputDecoration(
        filled: true,
        fillColor: RescueColors.panel,
        hintText: 'Найти программу, сайт или IP',
        prefixIcon: Icon(Icons.search_rounded, size: 18, color: RescueColors.muted),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: pill,
        enabledBorder: pill,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(999)),
          borderSide: BorderSide(color: RescueColors.accent, width: 1.5),
        ),
        semanticCounterText: '',
      ),
    );
    final note = Text(hint, style: RescueText.smallSecondary);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 560) {
          return Row(
            children: [
              Expanded(child: field),
              const SizedBox(width: 16),
              Flexible(child: note),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [field, const SizedBox(height: 10), note],
        );
      },
    );
  }
}
