import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/servers/model/servers_format.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../screens_test_helpers.dart';

const _url = 'https://vpn.example.com/sub/test-token';
const _old = [
  {'type': 'awg', 'tag': 'old'},
];
const _fresh = [
  {'type': 'awg', 'tag': 'fresh'},
];
const _links = 'vless://test@example.com:443#XHTTP';

class _HttpClient extends DioHttpClient {
  _HttpClient() : super(timeout: const Duration(seconds: 10), userAgent: 'test', debug: false);

  String body = jsonEncode(_fresh);
  Object? error;
  int status = 200;
  final requests = <String>[];
  final deviceIds = <String?>[];
  CancelToken? awgCancelToken;

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
    await File(path).writeAsString(url.endsWith('/links') ? _links : '{"outbounds":[],"route":{"final":"proxy"}}');
    return Response(requestOptions: RequestOptions(path: url), statusCode: 200);
  }

  @override
  Future<Response<T>> get<T>(
    String url, {
    CancelToken? cancelToken,
    String? userAgent,
    Map<String, dynamic>? headers,
    ({String username, String password})? credentials,
    bool proxyOnly = false,
  }) async {
    requests.add(url);
    deviceIds.add(headers?['X-Rescue-Device'] as String?);
    awgCancelToken = cancelToken;
    if (error != null) throw error!;
    return Response<T>(
      requestOptions: RequestOptions(path: url),
      data: body as T,
      statusCode: status,
    );
  }
}

DioException _failure(DioExceptionType type, [int? status]) => DioException(
  requestOptions: RequestOptions(path: 'test'),
  type: type,
  response: status == null
      ? null
      : Response(
          requestOptions: RequestOptions(path: 'test'),
          statusCode: status,
        ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late ProviderContainer container;
  late _HttpClient client;
  late ProfileParser parser;
  late File temp;
  late File saved;
  final profile = RemoteProfileEntity(
    id: 'test-profile',
    active: true,
    name: 'test',
    url: _url,
    lastUpdate: DateTime(2026),
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rescue-awg-test');
    container = await screensContainer(dir);
    client = _HttpClient();
    parser = container.read(Provider((ref) => ProfileParser(ref: ref, httpClient: client)));
    final resolver = ProfilePathResolver(dir);
    await resolver.directory.create();
    temp = resolver.tempFile(profile.id);
    saved = resolver.file(profile.id);
  });

  tearDown(() async {
    container.dispose();
    await dir.delete(recursive: true);
  });

  Future<Map<String, dynamic>> load({bool update = true, CancelToken? cancelToken}) async {
    final result =
        await (update
                ? parser.updateRemote(rp: profile, tempFilePath: temp.path, cancelToken: cancelToken)
                : parser.addRemote(
                    id: profile.id,
                    url: profile.url,
                    tempFilePath: temp.path,
                    userOverride: null,
                    cancelToken: cancelToken,
                  ))
            .run();
    expect(result.isRight(), isTrue);
    return jsonDecode(await temp.readAsString()) as Map<String, dynamic>;
  }

  test('200: endpoints and links survive; UUID v4 is persisted and reused by a new parser', () async {
    final token = CancelToken();
    final json = await load(cancelToken: token);
    expect(json['rescue-endpoints'], _fresh);
    expect(json['rescue-links'], _links);
    expect(json['route'], {'final': 'proxy'});
    expect(client.requests, [_url, '$_url/links', '$_url/awg']);
    expect(client.awgCancelToken, same(token));
    final id = client.deviceIds.single;
    expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(container.read(sharedPreferencesProvider).requireValue.getString('rescue-device-id'), id);
    parser = container.read(Provider((ref) => ProfileParser(ref: ref, httpClient: client)));
    await load();
    expect(client.deviceIds, [id, id]);
  });

  for (final exception in [false, true]) {
    test('404 removes endpoints, including previous ones (exception: $exception)', () async {
      await saved.writeAsString(jsonEncode({'rescue-endpoints': _old}));
      client.status = 404;
      if (exception) client.error = _failure(DioExceptionType.badResponse, 404);
      final json = await load();
      expect(json.containsKey('rescue-endpoints'), isFalse);
      expect(json['rescue-links'], _links);
    });
  }

  for (final scenario in ['503', '429', 'timeout', 'network', 'object', 'invalid JSON']) {
    for (final previous in [false, true]) {
      test('$scenario: ${previous ? 'keeps saved endpoints' : 'first add has no endpoints'}', () async {
        if (previous) await saved.writeAsString(jsonEncode({'rescue-endpoints': _old}));
        switch (scenario) {
          case '503':
          case '429':
            client.error = _failure(DioExceptionType.badResponse, int.parse(scenario));
          case 'timeout':
            client.error = _failure(DioExceptionType.receiveTimeout);
          case 'network':
            client.error = _failure(DioExceptionType.connectionError);
          case 'object':
            client.body = '{}';
          case 'invalid JSON':
            client.body = 'invalid';
        }
        final json = await load(update: previous);
        expect(json['rescue-endpoints'], previous ? _old : isNull);
        expect(json.containsKey('rescue-endpoints'), previous);
        expect(json['rescue-links'], _links);
      });
    }
  }

  test('fallback uses this profile file only', () async {
    await ProfilePathResolver(dir).file('another-profile').writeAsString(jsonEncode({'rescue-endpoints': _old}));
    client.error = _failure(DioExceptionType.connectionError);
    expect((await load()).containsKey('rescue-endpoints'), isFalse);
  });

  test('cancellation reaches the caller as cancelByUser', () async {
    await saved.writeAsString(jsonEncode({'rescue-endpoints': _old}));
    client.error = _failure(DioExceptionType.cancel);
    final result = await parser.updateRemote(rp: profile, tempFilePath: temp.path, cancelToken: CancelToken()).run();
    result.match(
      (failure) => expect(failure, isA<ProfileCancelByUserFailure>()),
      (_) => fail('Cancellation swallowed'),
    );
  });

  test('links merge preserves endpoints; both endpoint locations show AmneziaWG', () {
    final content = jsonEncode({'outbounds': [], 'rescue-endpoints': _fresh});
    final merged = jsonDecode(ProfileParser.withRescueLinks(content, _links)!) as Map<String, dynamic>;
    expect(merged['rescue-endpoints'], _fresh);
    expect(protocolsOfConfig({'outbounds': _old, 'rescue-endpoints': _fresh}), {
      'old': 'AmneziaWG',
      'fresh': 'AmneziaWG',
    });
    expect(ProfileParser.protocol('awg://test@example.com'), 'AmneziaWG');
  });

  test('saved profile: AmneziaWG from endpoints is named by protocol', () {
    // Ядро переносит rescue-endpoints в endpoints; без этого серверы назывались «Запасной N».
    expect(protocolsOfConfig({'outbounds': const [], 'endpoints': _fresh}), {'fresh': 'AmneziaWG'});
  });
}
