import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voteaxis/data/app_data.dart';
import 'package:voteaxis/models/issue.dart';
import 'package:voteaxis/models/pillar.dart';
import 'package:voteaxis/models/politician.dart';
import 'package:voteaxis/models/question.dart';
import 'package:voteaxis/services/device_token.dart';
import 'package:voteaxis/services/politicians_cache.dart';
import 'package:voteaxis/services/voteaxis_api.dart';

import 'support/fixtures.dart';

/// Answers every request with the same scripted response, ignoring headers —
/// enough to drive [AppData.refreshPoliticians] through its network client
/// without pulling in the private `_ScriptedClient` from voteaxis_api_test.
class _FixedClient extends http.BaseClient {
  _FixedClient(this.response);

  final http.Response response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: {'content-type': 'application/json', ...response.headers},
    );
  }
}

/// Routes by path, distinguishing `/v1/politicians` from `/v1/device-tokens`
/// — [_FixedClient] cannot, since it ignores the request entirely. Also
/// records every request's headers, keyed by path, for assertions on what
/// [AppData.refreshPoliticians] actually sent.
class _RouterClient extends http.BaseClient {
  _RouterClient(this.responses);

  final Map<String, http.Response> responses;
  final Map<String, Map<String, String>> lastHeadersByPath = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastHeadersByPath[request.url.path] = request.headers;
    final res = responses[request.url.path];
    if (res == null) {
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 404);
    }
    return http.StreamedResponse(
      Stream.value(res.bodyBytes),
      res.statusCode,
      headers: {'content-type': 'application/json', ...res.headers},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('profileFor uses the politician issue vector', () {
    final data = testAppData();
    final profile = data.profileFor(testPolitician());
    expect(profile.issueScores['taxes'], -40);
    expect(data.issuesById['taxes']?.label, 'Taxes');
    expect(data.pillarsById['economy']?.label, 'Economy');
  });

  test('withPoliticians swaps the roster and nothing else', () {
    final data = testAppData();
    final swapped = data.withPoliticians([testPolitician(id: 'new_person')]);
    expect(swapped.politicians.map((p) => p.id), ['new_person']);
    expect(swapped.pillars, data.pillars);
    expect(swapped.issues, data.issues);
    expect(swapped.questions, data.questions);
  });

  group('AppData roster caching and refresh', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    Directory tempDir() =>
        Directory.systemTemp.createTempSync('app_data_refresh_test');

    test('a successful fetch decodes politicians and caches the raw JSON', () async {
      final dir = tempDir();
      final api = VoteaxisApi(
        client: _FixedClient(
          http.Response(
            jsonEncode({
              'ok': true,
              'politicians': [
                {
                  'id': 'jane_example',
                  'name': 'Jane Example',
                  'role': 'Governor',
                  'party': 'Democratic',
                },
              ],
            }),
            200,
            headers: {'etag': 'W/"v2"'},
          ),
        ),
        baseUrl: 'http://voteaxis.test',
      );
      final cache = PoliticiansCache(directory: () async => dir);

      final result = await AppData.refreshPoliticians(api: api, cache: cache);

      expect(result, isNotNull);
      expect(result!.map((p) => p.id), ['jane_example']);
      expect(await cache.readEtag(), 'W/"v2"');
      expect(await cache.readRaw(), isNotNull);
    });

    test('a 304 leaves the existing cache untouched and returns null', () async {
      final dir = tempDir();
      final cache = PoliticiansCache(directory: () async => dir);
      await cache.write('[{"id":"old","name":"Old","role":"r","party":"p"}]',
          etag: 'W/"v1"');
      final api = VoteaxisApi(
        client: _FixedClient(http.Response('', 304)),
        baseUrl: 'http://voteaxis.test',
      );

      final result = await AppData.refreshPoliticians(api: api, cache: cache);

      expect(result, isNull);
      expect(await cache.readEtag(), 'W/"v1"');
    });

    test('a network failure is null, not a thrown exception', () async {
      final dir = tempDir();
      final cache = PoliticiansCache(directory: () async => dir);
      final api = VoteaxisApi(baseUrl: 'http://127.0.0.1:9');

      expect(
        await AppData.refreshPoliticians(api: api, cache: cache),
        isNull,
      );
    });

    test('AppData.load prefers a populated cache over the bundled asset', () async {
      final dir = tempDir();
      final cache = PoliticiansCache(directory: () async => dir);
      await cache.write(
        jsonEncode([
          {
            'id': 'cached_only',
            'name': 'Cached Only',
            'role': 'Test Role',
            'party': 'Independent',
          },
        ]),
      );

      final data = await AppData.load(cache: cache);

      expect(data.politicians.map((p) => p.id), ['cached_only']);
      // Bundled pillars/issues/questions still load normally — only the
      // politicians source is swapped.
      expect(data.pillars, isNotEmpty);
      expect(data.questions.length, greaterThan(50));
    });

    test('AppData.load falls back to the bundled asset with an empty cache', () async {
      final dir = tempDir();
      final cache = PoliticiansCache(directory: () async => dir);

      final data = await AppData.load(cache: cache);

      expect(data.politicians.length, greaterThanOrEqualTo(400));
    });

    test(
      'registers a device and signs the roster request on first use',
      () async {
        final client = _RouterClient({
          '/v1/device-tokens': http.Response(
            jsonEncode({'ok': true, 'deviceId': 'a'.padLeft(48, '0')}),
            200,
          ),
          '/v1/politicians': http.Response(
            jsonEncode({
              'ok': true,
              'politicians': [
                {
                  'id': 'jane_example',
                  'name': 'Jane Example',
                  'role': 'Governor',
                  'party': 'Democratic',
                },
              ],
            }),
            200,
          ),
        });
        final api = VoteaxisApi(client: client, baseUrl: 'http://voteaxis.test');
        final cache = PoliticiansCache(directory: () async => tempDir());

        final result = await AppData.refreshPoliticians(api: api, cache: cache);

        expect(result?.map((p) => p.id), ['jane_example']);
        final headers = client.lastHeadersByPath['/v1/politicians'];
        expect(headers?['x-voteaxis-device-id'], 'a'.padLeft(48, '0'));
        expect(headers?['x-voteaxis-nonce'], isNotNull);
        expect(headers?['x-voteaxis-signature'], isNotNull);
        // Persisted for next time, not just used in memory this once.
        expect(await DeviceIdentity().deviceId(), 'a'.padLeft(48, '0'));
      },
    );

    test(
      'reuses an already-registered device instead of registering again',
      () async {
        await DeviceIdentity().ensureRegistered((_) async => 'existing-device-id');
        final client = _RouterClient({
          // No handler for /v1/device-tokens — if refreshPoliticians called
          // it anyway, the 404 fallback would register nothing and the
          // header below would come back null instead of the stored value.
          '/v1/politicians': http.Response(
            jsonEncode({'ok': true, 'politicians': []}),
            200,
          ),
        });
        final api = VoteaxisApi(client: client, baseUrl: 'http://voteaxis.test');
        final cache = PoliticiansCache(directory: () async => tempDir());

        await AppData.refreshPoliticians(api: api, cache: cache);

        expect(
          client.lastHeadersByPath['/v1/politicians']?['x-voteaxis-device-id'],
          'existing-device-id',
        );
        expect(client.lastHeadersByPath.containsKey('/v1/device-tokens'), isFalse);
      },
    );
  });

  test('bundled JSON is a complete SII bank', () {
    final pillars =
        (jsonDecode(File('assets/data/pillars.json').readAsStringSync())
                as List)
            .map((e) => Pillar.fromJson(e as Map<String, dynamic>))
            .toList();
    final issues =
        (jsonDecode(File('assets/data/issues.json').readAsStringSync()) as List)
            .map((e) => Issue.fromJson(e as Map<String, dynamic>))
            .toList();
    final questions =
        (jsonDecode(File('assets/data/questions.json').readAsStringSync())
                as List)
            .map((e) => Question.fromJson(e as Map<String, dynamic>))
            .toList();
    final politicians =
        (jsonDecode(File('assets/data/politicians.json').readAsStringSync())
                as List)
            .map((e) => Politician.fromJson(e as Map<String, dynamic>))
            .toList();
    final data = AppData(
      pillars: pillars,
      issues: issues,
      questions: questions,
      politicians: politicians,
    );
    expect(data.politicians.length, greaterThanOrEqualTo(400));
    expect(data.questions.where((q) => q.isHistorical), hasLength(12));
    final issueIds = data.issues.map((i) => i.id).toSet();
    for (final q in data.questions) {
      expect(issueIds, contains(q.issueId));
      expect(q.hasSteelMan, isTrue, reason: q.id);
    }
    final obama = data.politicians.firstWhere((p) => p.id == 'barack_obama');
    expect(obama.servedSince(FigureFloor.year2000), isTrue);
    final reagan = data.politicians.firstWhere((p) => p.id == 'ronald_reagan');
    expect(reagan.servedSince(FigureFloor.year2000), isFalse);
    expect(reagan.servedSince(FigureFloor.year1980), isTrue);
  });
}
