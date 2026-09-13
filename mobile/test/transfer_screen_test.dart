import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:voteaxis/models/app_settings.dart';
import 'package:voteaxis/models/scoring.dart';
import 'package:voteaxis/screens/transfer_screen.dart';
import 'package:voteaxis/services/result_envelope.dart';
import 'package:voteaxis/services/share_link.dart';
import 'package:voteaxis/services/transfer_code.dart';
import 'package:voteaxis/services/voteaxis_api.dart';

const _profile = SpectrumProfile(
  issueScores: {'taxes': -40, 'climate': -70},
  pillarScores: {'economy': -40, 'world': -70},
  axisScore: -55,
  issueWeights: {'taxes': 2.5},
  dealbreakerIssueIds: ['climate'],
);

final _payload = TransferPayload.fromProfile(
  profile: _profile,
  settings: const AppSettings(skipQuiz: true),
  homeStateCode: 'MI',
);

const _id = 'a2b3c4d5e6f7g8h9';
const _token = 'ffffffffffffffffffffffffffffffffffffffffffffffff';

/// Records requests and replays canned responses keyed by `METHOD /path`.
class _FakeClient extends http.BaseClient {
  _FakeClient(this.script);

  final Map<String, http.Response> script;
  final requests = <({String method, String path, String body})>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    requests.add((method: request.method, path: request.url.path, body: body));
    final res = script['${request.method} ${request.url.path}'];
    if (res == null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"ok":false,"error":"unscripted"}')),
        500,
        headers: const {'content-type': 'application/json'},
      );
    }
    return http.StreamedResponse(
      Stream.value(res.bodyBytes),
      res.statusCode,
      headers: const {'content-type': 'application/json'},
    );
  }
}

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Map<String, dynamic> _linkBody({bool encrypted = false}) => {
  'ok': true,
  'id': _id,
  'token': _token,
  'url': 'https://voteaxis.org/result/$_id',
  'encrypted': encrypted,
  'expiresAt': DateTime.now()
      .add(const Duration(days: 90))
      .millisecondsSinceEpoch,
};

/// The plaintext an open link returns inline — and the same body a sealed
/// link yields once it is decrypted on the device.
Map<String, dynamic> _resultBody() => {
  'transferCode': TransferCode.encode(_payload),
  'axisScore': -55.0,
  'issueScores': {'taxes': -40.0},
  'issueWeights': <String, double>{},
  'pillarScores': {'economy': -40.0},
  'dealbreakerIssueIds': <String>[],
  'homeState': 'MI',
  'label': '',
};

/// Seals [_resultBody] the way the app would, so the screen has something real
/// to decrypt. Low iteration count keeps the widget tests fast.
///
/// The KDF runs on a real isolate, so every call and every tap that triggers a
/// decryption has to leave the fake clock behind via [WidgetTester.runAsync].
Future<Map<String, dynamic>> _sealedBody(String password) async {
  final envelope = await ResultEnvelope.seal(
    payload: _resultBody(),
    password: password,
    iterations: 1000,
  );
  return {
    'ok': true,
    'id': _id,
    'encrypted': true,
    'envelope': envelope.toJson(),
  };
}

/// Taps something that runs PBKDF2 on a real isolate.
///
/// `testWidgets` runs on a fake clock that never advances on its own, and the
/// isolate's result arrives on the real event loop, so the two have to be
/// stepped alternately. `pumpAndSettle` is no help either — the button shows
/// an indeterminate spinner while the work runs, so it would never settle.
Future<void> tapWithCrypto(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await tester.pump();
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  late List<MethodCall> clipboardCalls;
  String clipboardText = '';

  setUp(() {
    clipboardCalls = [];
    clipboardText = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          clipboardCalls.add(call);
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': clipboardText};
          }
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map)['text'] as String? ?? clipboardText;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// Pumps the screen inside a navigator so a pop can be observed.
  Future<TransferOutcome?> pump(
    WidgetTester tester, {
    TransferPayload? payload,
    SpectrumProfile? profile,
    StoredShareLink? existingLink,
    _FakeClient? client,
    Future<void> Function(StoredShareLink?)? onLinkChanged,
  }) async {
    TransferOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome = await Navigator.of(context).push<TransferOutcome>(
                MaterialPageRoute<TransferOutcome>(
                  builder: (_) => TransferScreen(
                    payload: payload,
                    profile: profile,
                    homeStateCode: 'MI',
                    existingLink: existingLink,
                    api: client == null
                        ? null
                        : VoteaxisApi(
                            client: client,
                            baseUrl: 'https://api.test',
                          ),
                    onLinkChanged: onLinkChanged,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return outcome;
  }

  group('with nothing saved', () {
    testWidgets('offers no link and says why', (tester) async {
      await pump(tester);
      expect(
        find.text('Take the quiz or set your level first.'),
        findsOneWidget,
      );
      expect(find.text('Create my link'), findsNothing);
      // Opening someone else's link is still available.
      expect(find.text('Open and restore'), findsOneWidget);
    });
  });

  group('creating a link', () {
    testWidgets('posts the profile and shows the URL', (tester) async {
      final client = _FakeClient({'POST /v1/results': _json(_linkBody())});
      StoredShareLink? saved;
      await pump(
        tester,
        payload: _payload,
        profile: _profile,
        client: client,
        onLinkChanged: (link) async => saved = link,
      );

      await tester.tap(find.text('Create my link'));
      await tester.pumpAndSettle();

      expect(find.text('https://voteaxis.org/result/$_id'), findsOneWidget);
      expect(find.textContaining('Anyone with the link'), findsOneWidget);
      expect(saved?.id, _id);
      expect(saved?.token, _token);

      // The offline code rides along so a restore is byte-exact.
      final body =
          jsonDecode(client.requests.single.body) as Map<String, dynamic>;
      final sent = body['payload'] as Map<String, dynamic>;
      expect(sent['axisScore'], -55);
      expect(sent['homeState'], 'MI');
      expect(TransferCode.decode(sent['transferCode'] as String), isNotNull);
      expect(body.containsKey('password'), isFalse);
    });

    testWidgets('a password uploads ciphertext, never the password', (
      tester,
    ) async {
      final client = _FakeClient({
        'POST /v1/results': _json(_linkBody(encrypted: true)),
      });
      await pump(tester, payload: _payload, profile: _profile, client: client);

      await tester.tap(find.text('Protect with a password'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'hunter2hunter2');
      await tapWithCrypto(tester, find.text('Create my link'));

      final body =
          jsonDecode(client.requests.single.body) as Map<String, dynamic>;
      // The whole point: nothing readable leaves the device.
      expect(body.containsKey('password'), isFalse);
      expect(body.containsKey('payload'), isFalse);
      final envelope = body['envelope'] as Map<String, dynamic>;
      expect(envelope['v'], ResultEnvelope.version);
      expect(envelope['kdf'], ResultEnvelope.kdf);

      final wire = client.requests.single.body;
      expect(wire.contains('hunter2'), isFalse);
      expect(wire.contains('axisScore'), isFalse);
      expect(wire.contains('VX1'), isFalse);

      // And it really is our result inside. Opening runs the KDF on a real
      // isolate, so it has to leave the fake clock behind as well.
      final sealed = ResultEnvelope.fromJson(envelope)!;
      final opened = await tester.runAsync(() => sealed.open('hunter2hunter2'));
      expect(opened?['axisScore'], -55);
      expect(opened?['homeState'], 'MI');

      expect(find.textContaining('Encrypted'), findsOneWidget);
    });

    testWidgets('refuses a password that is too short without calling out', (
      tester,
    ) async {
      final client = _FakeClient({'POST /v1/results': _json(_linkBody())});
      await pump(tester, payload: _payload, profile: _profile, client: client);

      await tester.tap(find.text('Protect with a password'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'short');
      await tester.tap(find.text('Create my link'));
      await tester.pumpAndSettle();

      expect(find.textContaining('at least 8 characters'), findsOneWidget);
      expect(client.requests, isEmpty);
    });

    testWidgets('surfaces a server error instead of a blank screen', (
      tester,
    ) async {
      final client = _FakeClient({
        'POST /v1/results': _json({
          'ok': false,
          'error': 'Too many links.',
        }, 429),
      });
      await pump(tester, payload: _payload, profile: _profile, client: client);
      await tester.tap(find.text('Create my link'));
      await tester.pumpAndSettle();
      expect(find.text('Too many links.'), findsOneWidget);
    });
  });

  group('an existing link', () {
    final existing = StoredShareLink(
      id: _id,
      token: _token,
      url: 'https://voteaxis.org/result/$_id',
      encrypted: false,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );

    testWidgets('reuses the same URL when updated', (tester) async {
      final client = _FakeClient({'POST /v1/results': _json(_linkBody())});
      await pump(
        tester,
        payload: _payload,
        profile: _profile,
        existingLink: existing,
        client: client,
      );
      await tester.tap(find.text('Update with my latest result'));
      await tester.pumpAndSettle();

      final body =
          jsonDecode(client.requests.single.body) as Map<String, dynamic>;
      expect(body['token'], _token);
    });

    testWidgets('copying puts the URL on the clipboard', (tester) async {
      await pump(
        tester,
        payload: _payload,
        profile: _profile,
        existingLink: existing,
      );
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(clipboardText, 'https://voteaxis.org/result/$_id');
      expect(find.text('Link copied'), findsOneWidget);
    });

    testWidgets('taking it down asks first, then revokes', (tester) async {
      final client = _FakeClient({
        'DELETE /v1/results/$_id': _json({'ok': true}),
      });
      StoredShareLink? saved = existing;
      var changed = false;
      await pump(
        tester,
        payload: _payload,
        profile: _profile,
        existingLink: existing,
        client: client,
        onLinkChanged: (link) async {
          saved = link;
          changed = true;
        },
      );

      await tester.tap(find.text('Take the link down'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(changed, isFalse);

      await tester.tap(find.text('Take the link down'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take it down'));
      await tester.pumpAndSettle();
      expect(changed, isTrue);
      expect(saved, isNull);
      expect(find.text('Create my link'), findsOneWidget);
    });
  });

  group('opening a link', () {
    testWidgets('an offline code restores with no network call', (
      tester,
    ) async {
      final client = _FakeClient(const {});
      final code = TransferCode.encode(_payload);
      final outcome = await pump(tester, client: client);

      await tester.enterText(find.byType(TextField).first, code);
      await tester.tap(find.text('Open and restore'));
      await tester.pumpAndSettle();

      expect(client.requests, isEmpty);
      expect(outcome, isNull, reason: 'outcome is captured after the pop');
      // The pop value lands once the route finishes unwinding.
      expect(find.text('Open and restore'), findsNothing);
    });

    testWidgets('a URL fetches the result and restores from its code', (
      tester,
    ) async {
      final client = _FakeClient({
        'GET /v1/results/$_id': _json({
          'ok': true,
          'id': _id,
          'encrypted': false,
          ..._resultBody(),
        }),
      });
      await pump(tester, client: client);

      await tester.enterText(
        find.byType(TextField).first,
        'https://voteaxis.org/result/$_id',
      );
      await tester.tap(find.text('Open and restore'));
      await tester.pumpAndSettle();

      expect(client.requests.single.path, '/v1/results/$_id');
      expect(find.text('Open and restore'), findsNothing);
    });

    testWidgets('an encrypted link is decrypted on the device', (tester) async {
      final client = _FakeClient({
        'GET /v1/results/$_id': _json(
          await tester.runAsync(() => _sealedBody('hunter2hunter2')) ?? {},
        ),
      });
      await pump(tester, client: client);

      await tester.enterText(find.byType(TextField).first, _id);
      await tester.tap(find.text('Open and restore'));
      await tester.pumpAndSettle();
      expect(find.text('This one is password protected.'), findsOneWidget);
      expect(find.text('Password for this link'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'hunter2hunter2');
      await tapWithCrypto(tester, find.text('Open and restore'));

      // The password never leaves the device: the only request was the fetch.
      expect(client.requests, hasLength(1));
      expect(client.requests.single.method, 'GET');
      expect(find.text('Open and restore'), findsNothing);
    });

    testWidgets('a wrong password fails locally with no extra request', (
      tester,
    ) async {
      final client = _FakeClient({
        'GET /v1/results/$_id': _json(
          await tester.runAsync(() => _sealedBody('hunter2hunter2')) ?? {},
        ),
      });
      await pump(tester, client: client);

      await tester.enterText(find.byType(TextField).first, _id);
      await tester.tap(find.text('Open and restore'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'wrongwrongwrong');
      await tapWithCrypto(tester, find.text('Open and restore'));

      expect(find.text('That password is not right.'), findsOneWidget);
      expect(find.text('Open and restore'), findsOneWidget);
      expect(client.requests, hasLength(1));
    });

    testWidgets('an empty password is caught before decrypting', (
      tester,
    ) async {
      final client = _FakeClient({
        'GET /v1/results/$_id': _json(
          await tester.runAsync(() => _sealedBody('hunter2hunter2')) ?? {},
        ),
      });
      await pump(tester, client: client);

      await tester.enterText(find.byType(TextField).first, _id);
      await tester.tap(find.text('Open and restore'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open and restore'));
      await tester.pumpAndSettle();

      expect(find.text('Enter the password for this link.'), findsOneWidget);
    });

    testWidgets('nonsense is rejected before any request', (tester) async {
      final client = _FakeClient(const {});
      await pump(tester, client: client);

      await tester.tap(find.text('Open and restore'));
      await tester.pumpAndSettle();
      expect(find.text('Paste a link or a code first.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'hello there');
      await tester.tap(find.text('Open and restore'));
      await tester.pumpAndSettle();
      expect(
        find.text("That doesn't look like a Voteaxis link or code."),
        findsOneWidget,
      );

      // A truncated VX1 code gets its own, more useful message.
      await tester.enterText(find.byType(TextField).first, 'VX1-ABCDE-FGHJK');
      await tester.tap(find.text('Open and restore'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Copy the whole thing'), findsOneWidget);

      expect(client.requests, isEmpty);
    });

    testWidgets('a link on the clipboard is filled in on open', (tester) async {
      clipboardText = 'https://voteaxis.org/result/$_id';
      await pump(tester, client: _FakeClient(const {}));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        'https://voteaxis.org/result/$_id',
      );
    });

    testWidgets('unrelated clipboard text is left alone', (tester) async {
      clipboardText = 'my grocery list';
      await pump(tester, client: _FakeClient(const {}));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        '',
      );
    });
  });

  group('the offline code', () {
    testWidgets('is tucked behind "No internet?" and copies', (tester) async {
      await pump(tester, payload: _payload, profile: _profile);
      expect(find.text('Copy offline code'), findsNothing);

      // The page grows a second Scrollable once the code is shown, so the
      // outer list has to be named explicitly.
      final page = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('No internet?'),
        200,
        scrollable: page,
      );
      await tester.tap(find.text('No internet?'));
      await tester.pumpAndSettle();

      // The list builds a little past the viewport, so scrollUntilVisible
      // finds the button without bringing it on screen.
      await tester.ensureVisible(find.text('Copy offline code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy offline code'));
      await tester.pumpAndSettle();
      expect(TransferCode.decode(clipboardText)?.homeStateCode, 'MI');
    });
  });
}
