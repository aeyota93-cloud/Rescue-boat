import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/compare/model/compare_models.dart';
import 'package:hiddify/features/compare/model/compare_target.dart';
import 'package:hiddify/features/compare/notifier/compare_notifier.dart';
import 'package:hiddify/features/overview/notifier/vpn_status.dart';
import 'package:hiddify/features/rescue_ui/rescue_ui.dart';
import 'package:hiddify/features/split_tunnel/model/split_tunnel.dart';
import 'package:hiddify/features/split_tunnel/notifier/split_tunnel_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Шлюпка: «Сравнить пути» — окно с двумя дорогами, «Напрямую» и «Через VPN».
Future<void> showComparePathsDialog(BuildContext context, CompareSubject subject) => showDialog<void>(
  context: context,
  builder: (_) => ComparePathsDialog(subject: subject),
);

/// Окно «Сравнить пути»: цель сверху, ход замеров, две карточки, вывод и кнопки «Мимо VPN» / «Через VPN».
///
/// Запрос уходит ядру сам, как только окно открыто и VPN подключён (или после ввода адреса). Пока VPN
/// не подключён, запрос не пишется. Закрытие окна отменяет замер и убирает файлы обмена.
class ComparePathsDialog extends HookConsumerWidget {
  const ComparePathsDialog({super.key, required this.subject});

  final CompareSubject subject;

  /// Ширина окна, с которой карточки стоят рядом (у диалога свои поля, а LayoutBuilder внутри AlertDialog
  /// не работает: тот меряет содержимое через IntrinsicWidth).
  static const sideBySideFrom = 640.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnOn = ref.watch(vpnStatusProvider.select((s) => s.on));
    final state = ref.watch(compareProvider);
    final notifier = ref.read(compareProvider.notifier);
    final selected = useState<CompareEndpoint?>(subject.endpoints.firstOrNull);
    final address = useTextEditingController();
    final addressText = useState('');
    final target = selected.value;

    // Запуск и остановка вслед за состоянием VPN и выбором цели (не во время сборки: провайдеры менять нельзя).
    useEffect(() {
      Future.microtask(() {
        if (!context.mounted) return;
        final current = ref.read(compareProvider);
        if (vpnOn && target != null && current.phase == ComparePhase.idle) {
          notifier.start(target);
        } else if (!vpnOn && current.running) {
          notifier.cancel();
        }
      });
      return null;
    }, [vpnOn, target]);

    void pick(CompareEndpoint endpoint) {
      selected.value = endpoint;
      if (vpnOn) notifier.start(endpoint);
    }

    final typed = parseCompareTarget(addressText.value);
    void submitAddress() {
      if (typed != null) pick(typed);
    }

    final item = target == null ? null : compareSplitItem(subject, target);

    return AlertDialog(
      scrollable: true,
      title: const Text('Сравнить пути'),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (subject.askAddress) ...[
              TextField(
                key: const ValueKey('compare-address'),
                controller: address,
                autofocus: true,
                onChanged: (v) => addressText.value = v,
                onSubmitted: (_) => submitAddress(),
                decoration: const InputDecoration(hintText: 'Сайт или IP: example.com, 8.8.8.8'),
              ),
              const SizedBox(height: 6),
              Text(
                addressText.value.trim().isEmpty || typed != null
                    ? 'Меряем время ответа напрямую и через VPN'
                    : 'Не понял адрес. Примеры: example.com, 8.8.8.8',
                style: RescueText.caption,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(onPressed: typed == null ? null : submitAddress, child: const Text('Сравнить')),
              ),
              const SizedBox(height: 16),
            ],
            _TargetBlock(
              subject: subject,
              selected: target,
              result: state.result,
              onPick: subject.askAddress ? null : pick,
            ),
            const SizedBox(height: 16),
            if (!vpnOn)
              const _Notice(icon: Icons.vpn_lock_rounded, text: 'Подключите VPN, чтобы сравнить пути')
            else if (target == null)
              _Notice(
                icon: Icons.info_outline_rounded,
                text: subject.askAddress
                    ? 'Введите адрес, и мы замерим обе дороги'
                    : 'Сейчас нет адресов, которые можно измерить. Откройте программу и повторите',
              )
            else ...[
              if (state.running) _Progress(state: state),
              if (state.running) const SizedBox(height: 16),
              _Cards(state: state),
              const SizedBox(height: 14),
              _VerdictLine(state: state),
              if (item != null) ...[
                const SizedBox(height: 18),
                _RouteButtons(item: item, recommended: state.verdict?.kind),
                if (subject.appExe != null) ...[
                  const SizedBox(height: 6),
                  Text('Правило для всей программы ${subject.appExe}', style: RescueText.caption),
                ],
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (vpnOn && target != null)
          TextButton(onPressed: state.finished ? notifier.retry : null, child: const Text('Повторить')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
      ],
    );
  }
}

// ---------- цель ----------

/// «ЦЕЛЬ»: адрес крупно, под ним IP и способ замера; у программы — выбор одной из её целей.
class _TargetBlock extends StatelessWidget {
  const _TargetBlock({required this.subject, required this.selected, required this.result, required this.onPick});

  final CompareSubject subject;
  final CompareEndpoint? selected;
  final CompareResult? result;
  final ValueChanged<CompareEndpoint>? onPick;

  @override
  Widget build(BuildContext context) {
    final target = selected;
    final app = subject.appExe;
    final result = this.result;
    final facts = [
      if (app != null) 'программа $app',
      if (result != null && result.ip.isNotEmpty && result.ip != target?.host) 'IP ${result.ip}',
      if (result != null && result.method == 'tls') 'время ответа по TLS',
      if (result != null && result.method == 'icmp') 'ping: сервер не отвечает по TCP',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('ЦЕЛЬ', style: RescueText.microLabel),
        const SizedBox(height: 6),
        if (target != null)
          Semantics(
            label: 'Цель: ${target.label}',
            child: ExcludeSemantics(
              child: Text(
                target.label,
                key: const ValueKey('compare-target'),
                style: RescueText.cardTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
        else
          const Text('Не выбрана', style: RescueText.smallSecondary),
        if (facts.isNotEmpty) ...[const SizedBox(height: 2), Text(facts.join(' · '), style: RescueText.caption)],
        if (onPick != null && subject.endpoints.length > 1) ...[
          const SizedBox(height: 10),
          const Text('Куда ходит программа сейчас. Выберите, что измерить:', style: RescueText.caption),
          const SizedBox(height: 8),
          FilterChips<CompareEndpoint>(
            options: [for (final e in subject.endpoints) (e, e.label)],
            selected: target ?? subject.endpoints.first,
            onSelected: onPick,
          ),
        ],
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return RescueCard.inset(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, size: 22, color: RescueColors.accent),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: RescueText.bodyStrong)),
        ],
      ),
    );
  }
}

// ---------- ход замеров ----------

class _Progress extends StatelessWidget {
  const _Progress({required this.state});

  final CompareState state;

  @override
  Widget build(BuildContext context) {
    final done = state.result?.samplesDone ?? 0;
    final text = state.result == null ? 'Ждём ядро…' : 'Замеряем: $done из ${state.expected}. Обычно это 10–20 секунд';
    return Semantics(
      container: true,
      label: text,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RescueProgressBar(key: const ValueKey('compare-progress'), value: state.progress),
            const SizedBox(height: 6),
            Text(text, style: RescueText.caption),
          ],
        ),
      ),
    );
  }
}

// ---------- карточки ----------

class _Cards extends StatelessWidget {
  const _Cards({required this.state});

  final CompareState state;

  @override
  Widget build(BuildContext context) {
    final result = state.result;
    final verdict = state.verdict;
    final direct = _PathCard(
      key: const ValueKey('compare-card-direct'),
      title: 'НАПРЯМУЮ',
      spoken: 'Напрямую',
      path: result?.direct,
      winner: verdict?.kind == VerdictKind.direct,
      waiting: state.running,
    );
    final vpn = _PathCard(
      key: const ValueKey('compare-card-vpn'),
      title: 'ЧЕРЕЗ VPN',
      spoken: 'Через VPN',
      path: result?.vpn,
      winner: verdict?.kind == VerdictKind.vpn,
      waiting: state.running,
    );
    if (MediaQuery.sizeOf(context).width >= ComparePathsDialog.sideBySideFrom) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: direct),
            const SizedBox(width: 12),
            Expanded(child: vpn),
          ],
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [direct, const SizedBox(height: 12), vpn]);
  }
}

/// Одна дорога: задержка (медиана) крупно, разброс, неудачи, первое подключение.
class _PathCard extends StatelessWidget {
  const _PathCard({
    super.key,
    required this.title,
    required this.spoken,
    required this.path,
    required this.winner,
    required this.waiting,
  });

  final String title;
  final String spoken;
  final PathResult? path;
  final bool winner;

  /// Замеры ещё идут: пустое место — «ждём», а не «нет данных».
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final path = this.path;
    final stats = path?.stats;
    final unavailable = path != null && !path.available && !path.estimate;
    final estimate = path?.estimate ?? false;
    final median = stats?.median;
    final String big;
    if (median != null) {
      big = formatMs(median);
    } else {
      big = '—';
    }
    final String? bigNote = median != null
        ? null
        : unavailable
        ? 'измерить нельзя'
        : (stats != null && stats.total > 0 && !waiting)
        ? 'не ответил'
        : (waiting ? 'ждём замеры' : null);

    String dash(String? v) => v ?? '—';
    final jitter = stats?.jitter;
    final failPercent = stats?.failPercent;
    final rows = <(String, String)>[
      ('Разброс', dash(jitter == null ? null : '±${jitter.round()} мс')),
      ('Неудачи', dash(failPercent == null ? null : '$failPercent %')),
      ('Первое подключение', dash(path?.firstMs == null ? null : formatMs(path!.firstMs!))),
    ];
    final note = path?.note ?? '';

    final spokenText = [
      spoken,
      if (winner) 'лучше',
      if (estimate) 'оценка качества туннеля',
      if (median != null) 'задержка $big' else if (bigNote != null) bigNote,
      for (final (k, v) in rows) '$k $v',
      if (note.isNotEmpty) note,
    ].join(', ');

    return Semantics(
      container: true,
      label: spokenText,
      child: ExcludeSemantics(
        child: RescueCard(
          color: RescueColors.panel,
          radius: 20,
          padding: const EdgeInsets.all(16),
          borderColor: winner ? RescueColors.accent : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Высота строки — как с плашкой «ЛУЧШЕ», чтобы цифры в двух карточках стояли на одном уровне.
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 24),
                child: Row(
                  children: [
                    Expanded(child: Text(title, style: RescueText.microLabel)),
                    if (winner) const RescueBadge(label: 'ЛУЧШЕ', kind: RescueBadgeKind.success),
                  ],
                ),
              ),
              if (estimate) ...[
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: RescueBadge.tag(label: 'ОЦЕНКА: КАЧЕСТВО ТУННЕЛЯ', kind: RescueBadgeKind.bypass),
                ),
              ],
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(big, key: ValueKey('compare-median-$title'), style: RescueText.bigLight),
              ),
              if (bigNote != null) Text(bigNote, style: RescueText.caption),
              const SizedBox(height: 10),
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(k, style: RescueText.smallSecondary)),
                      const SizedBox(width: 8),
                      Text(v, style: RescueText.small.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              if (note.isNotEmpty) ...[const SizedBox(height: 8), Text(note, style: RescueText.caption)],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- вывод и кнопки ----------

class _VerdictLine extends StatelessWidget {
  const _VerdictLine({required this.state});

  final CompareState state;

  @override
  Widget build(BuildContext context) {
    final verdict = state.verdict;
    final (IconData, Color, String)? shown = switch (state.phase) {
      ComparePhase.idle || ComparePhase.running => null,
      ComparePhase.failed => (
        Icons.error_outline_rounded,
        RescueColors.warn,
        'Не удалось сравнить: ${state.error.isEmpty ? 'ядро вернуло ошибку' : state.error}',
      ),
      ComparePhase.timedOut => (
        Icons.hourglass_empty_rounded,
        RescueColors.warn,
        'Ядро не ответило за 90 секунд. Попробуйте ещё раз',
      ),
      ComparePhase.done when verdict != null => (
        switch (verdict.kind) {
          VerdictKind.direct => Icons.call_made_rounded,
          VerdictKind.vpn => Icons.vpn_key_rounded,
          VerdictKind.same => Icons.drag_handle_rounded,
          VerdictKind.notComparable || VerdictKind.noData => Icons.info_outline_rounded,
        },
        switch (verdict.kind) {
          VerdictKind.direct || VerdictKind.vpn => RescueColors.accent,
          VerdictKind.noData => RescueColors.warn,
          _ => RescueColors.text,
        },
        verdict.text,
      ),
      ComparePhase.done => null,
    };
    if (shown == null) return const SizedBox.shrink();
    final (icon, color, text) = shown;
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                key: const ValueKey('compare-verdict'),
                style: RescueText.cardTitle.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Пустить мимо VPN» / «Всегда через VPN»: добавляют цель в списки туннеля. Жёлтая — только кнопка лучшей
/// дороги; пока вывода нет (или разницы нет), обе одинаковые.
class _RouteButtons extends ConsumerWidget {
  const _RouteButtons({required this.item, required this.recommended});

  final ({SplitKind kind, String value}) item;
  final VerdictKind? recommended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(splitTunnelProvider).targetOf(item.kind, item.value);

    VoidCallback? add(SplitTarget target) => current == target
        ? null
        : () {
            ref.read(splitTunnelProvider.notifier).add(target, item.kind, item.value);
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(SnackBar(content: Text('Добавлено в «${target.title}»: ${item.value}')));
          };

    final bypass = Text(current == SplitTarget.bypass ? 'Уже мимо VPN' : 'Пустить мимо VPN');
    final via = Text(current == SplitTarget.via ? 'Уже через VPN' : 'Всегда через VPN');
    Widget bypassButton(bool primary) => primary
        ? FilledButton(onPressed: add(SplitTarget.bypass), child: bypass)
        : OutlinedButton(onPressed: add(SplitTarget.bypass), child: bypass);
    Widget viaButton(bool primary) => primary
        ? FilledButton(onPressed: add(SplitTarget.via), child: via)
        : OutlinedButton(onPressed: add(SplitTarget.via), child: via);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [bypassButton(recommended == VerdictKind.direct), viaButton(recommended == VerdictKind.vpn)],
    );
  }
}
