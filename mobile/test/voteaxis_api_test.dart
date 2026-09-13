import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:voteaxis/models/scoring.dart';
import 'package:voteaxis/services/device_token.dart';
import 'package:voteaxis/services/voteaxis_api.dart';

class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this.script);

  final Map<String, http.Response> script;
  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = '${request.method} ${request.url.path}';
    final res = script[key];
    if (res == null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":"unscripted $key"}')),
        500,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.StreamedResponse(
      Stream.value(res.bodyBytes),
      res.statusCode,
      headers: {'content-type': 'application/json', ...res.headers},
    );
  }
}

/// Records the last request's headers so a test can assert on what was sent,
/// then answers with a fixed response.
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.response);

  final http.Response response;
  Map<String, String>? lastRequestHeaders;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequestHeaders = request.headers;
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: {'content-type': 'application/json', ...response.headers},
    );
  }
}

void main() {
  const profile = SpectrumProfile(
    issueScores: {'taxes': -40},
    pillarScores: {'economy': -40},
    axisScore: -40,
  );

  test('publish posts the profile and returns a code', () async {
    final api = VoteaxisApi(
      client: _ScriptedClient({
        'POST /v1/codes': http.Response(
          jsonEncode({'code': 'A2B3C4', 'token': 'tok', 'expiresAt': 1}),
          200,
        ),
      }),
      baseUrl: 'http://voteaxis.test',
    );
    final published = await api.publish(profile: profile, displayName: 'Alex');
    expect(published.code, 'A2B3C4');
    expect(published.token, 'tok');
  });

  test('lookup 404 becomes ApiException', () async {
    final api = VoteaxisApi(
      client: _ScriptedClient({
        'GET /v1/codes/ZZZZZZ': http.Response(
          '{"error":"Code expired or not found."}',
          404,
        ),
      }),
      baseUrl: 'http://voteaxis.test',
    );
    expect(
      () => api.lookup('ZZZZZZ'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
    );
  });

  test('week JSON maps onto IssueOfTheWeek', () async {
    final api = VoteaxisApi(
      client: _ScriptedClient({
        'GET /v1/week': http.Response(
          jsonEncode({
            'weekOf': '2026-08-10',
            'issueId': 'immigration',
            'headline': 'Who belongs?',
            'question': 'Expand legal paths or tighten enforcement?',
            'context': 'Editorial prompt.',
          }),
          200,
        ),
      }),
      baseUrl: 'http://voteaxis.test',
    );
    final week = await api.week();
    expect(week?.issueId, 'immigration');
    expect(week?.headline, 'Who belongs?');
    expect(week?.context, isNotEmpty);
  });

  test('week 404 is null, not an exception', () async {
    final api = VoteaxisApi(
      client: _ScriptedClient({
        'GET /v1/week': http.Response('{"error":"No issue of the week."}', 404),
      }),
      baseUrl: 'http://voteaxis.test',
    );
    expect(await api.week(), isNull);
  });

  test('receipts parse sponsored bills', () async {
    final api = VoteaxisApi(
      client: _ScriptedClient({
        'GET /v1/receipts/S000033': http.Response(
          jsonEncode({
            'bioguideId': 'S000033',
            'memberUrl': 'https://bioguide.congress.gov/search/bio/S000033',
            'sponsored': [
              {
                'kind': 'sponsored',
                'congress': 118,
                'type': 'S',
                'number': '1655',
                'title': 'Medicare for All Act',
                'url':
                    'https://www.congress.gov/bill/118th-congress/senate-bill/1655',
                'latestAction':
                    '2023-05-17 - Read twice and referred to the Committee on Finance.',
                'summary':
                    'This bill establishes national health insurance. It also sets a timeline for states.',
                'enrichedFrom': 'congress.gov',
              },
            ],
            'cosponsored': [],
          }),
          200,
        ),
      }),
      baseUrl: 'http://voteaxis.test',
    );
    final receipts = await api.receipts('S000033');
    expect(receipts.sponsored.single.citation, 'S 1655 · 118th');
    expect(
      receipts.sponsored.single.summary,
      contains('national health insurance'),
    );
    expect(receipts.sponsored.single.enrichedFrom, 'congress.gov');
    expect(receipts.sponsored.single.latestAction, contains('Read twice'));
  });

  test('dispose() leaves an injected client alone', () {
    // The owner of an injected client controls its lifecycle — closing it here
    // would break a caller that reuses it.
    final client = _ScriptedClient(const {});
    VoteaxisApi(client: client, baseUrl: 'http://voteaxis.test').dispose();
    expect(client.closed, isFalse);
  });

  test('dispose() closes the client it created', () async {
    // No client injected → VoteaxisApi owns one, and dispose() must close it.
    // A request afterwards fails at "client is already closed", before any I/O.
    final api = VoteaxisApi(baseUrl: 'http://127.0.0.1:9');
    api.dispose();
    await expectLater(api.week(), throwsA(isA<http.ClientException>()));
  });

  test('fetchPoliticians returns the array and the ETag', () async {
    final api = VoteaxisApi(
      client: _ScriptedClient({
        'GET /v1/politicians': http.Response(
          jsonEncode({
            'ok': true,
            'total': 1,
            'count': 1,
            'politicians': [
              {'id': 'jane_example', 'name': 'Jane Example'},
            ],
          }),
          200,
          headers: {'etag': 'W/"123:456"'},
        ),
      }),
      baseUrl: 'http://voteaxis.test',
    );
    final snapshot = await api.fetchPoliticians();
    expect(snapshot, isNotNull);
    expect(snapshot!.etag, 'W/"123:456"');
    expect(jsonDecode(snapshot.raw), [
      {'id': 'jane_example', 'name': 'Jane Example'},
    ]);
  });

  test('fetchPoliticians sends the cached ETag as If-None-Match', () async {
    final client = _RecordingClient(
      http.Response(jsonEncode({'ok': true, 'politicians': []}), 200),
    );
    final api = VoteaxisApi(client: client, baseUrl: 'http://voteaxis.test');
    await api.fetchPoliticians(etag: 'W/"abc"');
    expect(client.lastRequestHeaders?['if-none-match'], 'W/"abc"');
  });

  test('fetchPoliticians omits If-None-Match with no cached ETag', () async {
    final client = _RecordingClient(
      http.Response(jsonEncode({'ok': true, 'politicians': []}), 200),
    );
    final api = VoteaxisApi(client: client, baseUrl: 'http://voteaxis.test');
    await api.fetchPoliticians();
    expect(client.lastRequestHeaders?.containsKey('if-none-match'), isFalse);
  });

  test('fetchPoliticians sends the configured key as x-voteaxis-key', () async {
    final client = _RecordingClient(
      http.Response(jsonEncode({'ok': true, 'politicians': []}), 200),
    );
    final api = VoteaxisApi(client: client, baseUrl: 'http://voteaxis.test');
    await api.fetchPoliticians(key: 'personal-key');
    expect(client.lastRequestHeaders?['x-voteaxis-key'], 'personal-key');
  });

  test('fetchPoliticians omits x-voteaxis-key when no key is set', () async {
    final client = _RecordingClient(
      http.Response(jsonEncode({'ok': true, 'politicians': []}), 200),
    );
    final api = VoteaxisApi(client: client, baseUrl: 'http://voteaxis.test');
    await api.fetchPoliticians(key: '');
    expect(client.lastRequestHeaders?.containsKey('x-voteaxis-key'), isFalse);
  });

  test('fetchPoliticians treats a locked-down 401 as "nothing to show", not an error', () async {
    // Matches the server's default: no POLITICIANS_API_KEY configured, or
    // this build's key is wrong/missing. Either way the caller keeps
    // whatever roster it already has instead of surfacing a failure.
    final api = VoteaxisApi(
      client: _ScriptedClient({
        'GET /v1/politicians': http.Response('{"ok":false}', 401),
      }),
      baseUrl: 'http://voteaxis.test',
    );
    expect(await api.fetchPoliticians(key: 'wrong'), isNull);
  });

  test('fetchPoliticians sends all four device auth headers', () async {
    final client = _RecordingClient(
      http.Response(jsonEncode({'ok': true, 'politicians': []}), 200),
    );
    final api = VoteaxisApi(client: client, baseUrl: 'http://voteaxis.test');
    final auth = DeviceAuthHeaders(
      deviceId: 'a'.padLeft(48, '0'),
      timestamp: 1234567890,
      nonce: 'deadbeef',
      signatureHex: 'aa',
    );
    await api.fetchPoliticians(key: '', deviceAuth: auth);
    expect(client.lastRequestHeaders?['x-voteaxis-device-id'], auth.deviceId);
    expect(client.lastRequestHeaders?['x-voteaxis-timestamp'], '1234567890');
    expect(client.lastRequestHeaders?['x-voteaxis-nonce'], 'deadbeef');
    expect(client.lastRequestHeaders?['x-voteaxis-signature'], 'aa');
  });

  test('fetchPoliticians omits device auth headers with no deviceAuth', () async {
    final client = _RecordingClient(
      http.Response(jsonEncode({'ok': true, 'politicians': []}), 200),
    );
    final api = VoteaxisApi(client: client, baseUrl: 'http://voteaxis.test');
    await api.fetchPoliticians(key: '');
    expect(
      client.lastRequestHeaders?.containsKey('x-voteaxis-device-id'),
      isFalse,
    );
    expect(
      client.lastRequestHeaders?.containsKey('x-voteaxis-signature'),
      isFalse,
    );
  });

  test('registerDevice sends the public key and returns the assigned deviceId', () async {
    final client = _RecordingClient(
      http.Response(
        jsonEncode({'ok': true, 'deviceId': 'a'.padLeft(48, '0'), 'issuedAt': 1}),
        200,
      ),
    );
    final api = VoteaxisApi(client: client, baseUrl: 'http://voteaxis.test');
    final deviceId = await api.registerDevice('b'.padLeft(64, '0'));
    expect(deviceId, 'a'.padLeft(48, '0'));
    expect(client.lastRequestHeaders?['content-type'], 'application/json');
  });

  test('registerDevice is best-effort: failure is null, not a throw', () async {
    final api = VoteaxisApi(
      client: _ScriptedClient({
        'POST /v1/device-tokens': http.Response('{"ok":false}', 429),
      }),
      baseUrl: 'http://voteaxis.test',
    );
    expect(await api.registerDevice('b'.padLeft(64, '0')), isNull);
  });

  test('registerDevice is null on an unreachable host', () async {
    final api = VoteaxisApi(baseUrl: 'http://127.0.0.1:9');
    expect(await api.registerDevice('b'.padLeft(64, '0')), isNull);
  });

  test('fetchPoliticians treats 304 as "nothing changed"', () async {
    final api = VoteaxisApi(
      client: _ScriptedClient({
        'GET /v1/politicians': http.Response('', 304),
      }),
      baseUrl: 'http://voteaxis.test',
    );
    expect(await api.fetchPoliticians(etag: 'W/"abc"'), isNull);
  });

  test('fetchPoliticians is best-effort: a server error is null, not a throw', () async {
    // _ScriptedClient answers 500 for any request it wasn't told about.
    final api = VoteaxisApi(
      client: _ScriptedClient(const {}),
      baseUrl: 'http://voteaxis.test',
    );
    expect(await api.fetchPoliticians(), isNull);
  });

  test('fetchPoliticians is null on an unreachable host, not a throw', () async {
    final api = VoteaxisApi(baseUrl: 'http://127.0.0.1:9');
    expect(await api.fetchPoliticians(), isNull);
  });

  test('bill citations cover House and Senate forms', () {
    expect(
      CongressBill.fromJson({
        'congress': 116,
        'type': 'HRES',
        'number': 109,
        'title': 'Green New Deal',
        'url': 'https://example.test',
      }).citation,
      'H.Res. 109 · 116th',
    );
    expect(
      CongressBill.fromJson({
        'congress': 107,
        'type': 'SJRES',
        'number': '23',
        'title': 'AUMF',
        'url': 'https://example.test',
      }).citation,
      'S.J.Res. 23 · 107th',
    );
  });
}
