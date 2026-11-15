import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_data_source.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:toastification/toastification.dart';

import '../features/screens_test_helpers.dart';

const auditTimeout = Timeout(Duration(seconds: 5));
const validUri = 'vless://00000000-0000-0000-0000-000000000001@example.test:443#first';
const profileUrl = 'https://subscription.test/main';

Future<T> auditWait<T>(Future<T> future, String id, {int seconds = 2}) => future.timeout(
  Duration(seconds: seconds),
  onTimeout: () => fail('$id: ожидали завершение за $seconds с, получили незавершённую операцию'),
);

Future<Object?> outcome(Future<dynamic> future) => future.then<Object?>((_) => null, onError: (Object e) => e);

Future<void> flushAudit() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}

RemoteProfileEntity remote({String id = 'p1', String url = profileUrl, bool active = true}) => RemoteProfileEntity(
  id: id,
  active: active,
  name: 'Полная подписка',
  url: url,
  lastUpdate: DateTime(2026, 11),
  userOverride: const UserOverride(name: 'Полная подписка'),
);

OutboundGroup groupOf({String prefix = 'srv', int count = 2, int delay = 20}) => OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: '${prefix}0',
  items: List.generate(
    count,
    (i) => OutboundInfo(tag: '$prefix$i', tagDisplay: 'Сервер $i', type: 'vless', urlTestDelay: delay),
  ),
);

/// Подмена только HTTP-границы. Парсер, expansion и репозиторий остаются настоящими.
class MemoryDownloads extends DioHttpClient {
  MemoryDownloads() : super(timeout: const Duration(seconds: 1), userAgent: 'audit', debug: false);
  final bodies = <String, String>{profileUrl: validUri};
  final failures = <String>{};
  final requests = <String>[];
  @override
  Future<Response> download(
    String url,
    String path, {
    CancelToken? cancelToken,
    String? userAgent,
    Map<String, dynamic>? headers,
    ({String username, String password})? credentials,
    bool proxyOnly = false,
  }) async {
    requests.add(url);
    if (failures.contains(url) || !bodies.containsKey(url)) {
      throw DioException(
        requestOptions: RequestOptions(path: url),
        type: DioExceptionType.connectionError,
      );
    }
    if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
    await File(path).writeAsString(bodies[url]!);
    return Response(
      requestOptions: RequestOptions(path: url),
      statusCode: 200,
      headers: Headers(),
    );
  }
}

/// Источник БД в памяти; не подменяет поведение ProfileRepositoryImpl.
class MemoryProfiles implements ProfileDataSource {
  MemoryProfiles(List<ProfileEntity> profiles) {
    for (final p in profiles) {
      final c = p.toInsertEntry();
      entries[p.id] = ProfileEntry(
        id: p.id,
        type: c.type.value,
        active: p.active,
        name: p.name,
        url: c.url.value,
        lastUpdate: p.lastUpdate,
        userOverride: c.userOverride.value,
      );
    }
  }
  final entries = <String, ProfileEntry>{};
  final changes = StreamController<void>.broadcast();
  Completer<ProfileEntry?>? getGate;
  final getEntered = Completer<void>();
  int edits = 0;
  int activeReads = 0;
  @override
  Future<ProfileEntry?> getById(String id) async {
    if (!getEntered.isCompleted) getEntered.complete();
    return getGate == null ? entries[id] : await getGate!.future;
  }

  @override
  Future<ProfileEntry?> getByUrl(String url) async => entries.values.where((p) => p.url == url).firstOrNull;
  @override
  Future<ProfileEntry?> getByName(String name) async => entries.values.where((p) => p.name == name).firstOrNull;
  @override
  Future<void> insert(ProfileEntriesCompanion c) async {
    entries[c.id.value] = ProfileEntry(
      id: c.id.value,
      type: c.type.value,
      active: c.active.value,
      name: c.name.value,
      url: c.url.value,
      lastUpdate: c.lastUpdate.value,
    ).copyWithCompanion(c);
    changes.add(null);
  }

  @override
  Future<void> edit(String id, ProfileEntriesCompanion c) async {
    edits++;
    if (entries[id] case final p?) entries[id] = p.copyWithCompanion(c);
    changes.add(null);
  }

  @override
  Future<void> deleteById(String id, bool isActive) async {
    entries.remove(id);
    changes.add(null);
  }

  @override
  Stream<ProfileEntry?> watchActiveProfile() async* {
    activeReads++;
    yield entries.values.where((p) => p.active).firstOrNull;
    await for (final _ in changes.stream) {
      yield entries.values.where((p) => p.active).firstOrNull;
    }
  }

  @override
  Stream<int> watchProfilesCount() async* {
    yield entries.length;
    yield* changes.stream.map((_) => entries.length);
  }

  @override
  Stream<List<ProfileEntry>> watchAll({required ProfilesSort sort, required SortMode sortMode}) async* {
    yield entries.values.toList();
    yield* changes.stream.map((_) => entries.values.toList());
  }
}

class ToastSpy extends InAppNotificationController {
  final successes = <String>[];
  @override
  ToastificationItem? showSuccessToast(String message) {
    successes.add(message);
    return null;
  }

  @override
  ToastificationItem? showErrorToast(String message) => null;
}

/// Внешнее ядро: файлы только в temp теста, ответы и RPC управляются барьерами.
class MemoryCore extends HiddifyCoreService {
  MemoryCore(super.ref, {OutboundGroup? group}) : groups = BehaviorSubject.seeded(group ?? groupOf());
  final BehaviorSubject<OutboundGroup?> groups;
  final statuses = BehaviorSubject<CoreStatus>.seeded(const CoreStatus.started());
  final gates = <String, Completer<void>>{};
  final entered = StreamController<String>.broadcast();
  final validations = <String>[];
  bool rejectValidation = false;
  int configReads = 0;
  Completer<void>? selectGate;
  final selectEntered = Completer<void>();
  @override
  TaskEither<String, Unit> changeOptions(SingboxConfigOption options) => TaskEither.right(unit);
  @override
  TaskEither<String, Unit> validateConfigByPath(String path, String tempPath, bool debug) => TaskEither(() async {
    validations.add(path);
    entered.add(path);
    if (gates[path] case final gate?) await gate.future;
    if (rejectValidation) return left('audit: ядро отклонило конфиг');
    await File(path).writeAsString(await File(tempPath).readAsString());
    return right(unit);
  });
  @override
  TaskEither<String, String> generateFullConfigByPath(String path) => TaskEither(() async {
    configReads++;
    return right('{"outbounds":[],"endpoints":[]}');
  });
  @override
  Stream<CoreStatus> watchStatus() => statuses.stream;
  @override
  TaskEither<String, Unit> stop() => TaskEither.right(unit);
  @override
  TaskEither<ConnectionFailure, Unit> start(String path, String name, bool disableMemoryLimit) =>
      TaskEither.right(unit);
  @override
  TaskEither<String, Unit> urlTest(String groupTag) => TaskEither.right(unit);
  @override
  Stream<OutboundGroup?> watchGroup() => groups.stream;
  @override
  Stream<List<OutboundGroup>> watchActiveGroups() => groups.stream.map((g) => g == null ? [] : [g]);
  @override
  TaskEither<String, Unit> selectOutbound(String groupTag, String outboundTag) => TaskEither(() async {
    if (!selectEntered.isCompleted) selectEntered.complete();
    if (selectGate != null) await selectGate!.future;
    return right(unit);
  });
}

class AuditHarness {
  AuditHarness._(this.dir, this.container, this.db, this.http, this.core, this.toasts);
  final Directory dir;
  final ProviderContainer container;
  final MemoryProfiles db;
  final MemoryDownloads http;
  final MemoryCore core;
  final ToastSpy toasts;
  ProfilePathResolver get paths => container.read(profilePathResolverProvider);
  ProfileRepository get repo => container.read(profileRepositoryProvider).requireValue;

  static Future<AuditHarness> create({
    List<ProfileEntity>? profiles,
    OutboundGroup? group,
    Map<String, Object> prefs = const {},
    List<Override> overrides = const [],
  }) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory.systemTemp.createTempSync('shlupki_audit_');
    final db = MemoryProfiles(profiles ?? [remote()]);
    final http = MemoryDownloads();
    final toasts = ToastSpy();
    late MemoryCore core;
    final container = await screensContainer(
      dir,
      prefs: {'haptic_feedback': false, ...prefs},
      overrides: [
        profileDataSourceProvider.overrideWithValue(db),
        httpClientProvider.overrideWithValue(http),
        hiddifyCoreServiceProvider.overrideWith((ref) => core = MemoryCore(ref, group: group)),
        inAppNotificationControllerProvider.overrideWithValue(toasts),
        ...overrides,
      ],
    );
    await auditWait(container.read(translationsProvider.future), 'подготовка');
    await auditWait(container.read(profileRepositoryProvider.future), 'подготовка');
    return AuditHarness._(dir, container, db, http, core, toasts);
  }

  Future<void> close() async {
    for (final gate in core.gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
    if (core.selectGate case final gate? when !gate.isCompleted) gate.complete();
    container.dispose();
    await flushAudit();
    await auditWait(core.groups.close(), 'очистка');
    await auditWait(core.statuses.close(), 'очистка');
    await auditWait(core.entered.close(), 'очистка');
    await auditWait(db.changes.close(), 'очистка');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

Future<void> mountAudit(WidgetTester tester, AuditHarness h, Widget page) async {
  await pumpPage(tester, h.container, page, size: const Size(1440, 900));
}
