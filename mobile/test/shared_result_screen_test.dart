import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:voteaxis/models/app_settings.dart';
import 'package:voteaxis/models/scoring.dart';
import 'package:voteaxis/screens/shared_result_screen.dart';
import 'package:voteaxis/screens/transfer_screen.dart';
import 'package:voteaxis/services/result_envelope.dart';
import 'package:voteaxis/services/transfer_code.dart';
import 'package:voteaxis/services/voteaxis_api.dart';
import 'package:voteaxis/theme/app_theme.dart';

import 'support/fixtures.dart';

const _id = 'a2b3c4d5e6f7g8h9';

const _profile = SpectrumProfile(
  issueScores: {'taxes': -40, 'climate': -70},
  pillarScores: {'economy': -40, 'world': -70},
  axisScore: -55,
  issueWeights: {'taxes': 2.5},
  dealbreakerIssueIds: ['climate'],
);

final _payload = TransferPayload.fromProfile(
  profile: _profile,
  settings: const AppSettings(),
  homeStateCode: 'MI',
);

/// Same scripted-client approach as transfer_screen_test: canned responses
/// keyed by `METHOD /path`, every request recorded.
class _FakeClient extends http.BaseClient {
  _FakeClient(this.script);

  final Map<String, http.Response> script;
  final requests = <({String method, String path})>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add((method: request.method, path: request.url.path));
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

Map<String, dynamic> _resultBody({String label = ''}) => {
  'ok': true,
  'id': _id,
  'encrypted': false,
  'transferCode': TransferCode.encode(_payload),
  'axisScore': -55.0,
  'issueScores': {'taxes': -40.0, 'climate': -70.0},
  'issueWeights': <String, double>{'taxes': 2.5},
  'pillarScores': {'economy': -40.0},
  'dealbreakerIssueIds': <String>['climate'],
  'homeState': 'MI',
  'label': label,
};

/// PBKDF2 runs on a real isolate — same stepping as transfer_screen_test.
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
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(
    WidgetTester tester, {
    _FakeClient? client,
    SpectrumProfile? userProfile,
    void Function(TransferOutcome)? onPopped,
  }) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final outcome = await Navigator.of(context).push<TransferOutcome>(
                MaterialPageRoute<TransferOutcome>(
                  builder: (_) => SharedResultScreen(
                    resultId: _id,
                    data: testAppData(),
                    userProfile: userProfile,
                    api: client == null
                        ? null
                        : VoteaxisApi(
                            client: client,
                            baseUrl: 'https://api.test',
                          ),
                  ),
                ),
              );
              if (outcome != null) onPopped?.call(outcome);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('fetches the result and shows the shared placement', (
    tester,
  ) async {
    final client = _FakeClient({
      'GET /v1/results/$_id': http.Response(jsonEncode(_resultBody()), 200),
    });
    await pump(tester, client: client);

    expect(client.requests.single.path, '/v1/results/$_id');
    expect(find.text('Strongly liberal'), findsOneWidget);
    expect(find.text('Use as my placement'), findsOneWidget);
    // Nobody's placement is on this device — no compare affordance.
    expect(find.text('You'), findsNothing);
  });

  testWidgets('with a profile, shows the side-by-side and the overlap', (
    tester,
  ) async {
    final client = _FakeClient({
      'GET /v1/results/$_id': http.Response(jsonEncode(_resultBody()), 200),
    });
    await pump(tester, client: client, userProfile: testProfile());

    expect(find.text('You'), findsOneWidget);
    expect(find.text('Replace mine with this'), findsOneWidget);
    // The Venn section only renders when a viewer profile exists.
    expect(find.text('WHERE YOU OVERLAP'), findsOneWidget);
  });

  testWidgets('a 404 says the link is gone and offers a retry', (tester) async {
    final client = _FakeClient({
      'GET /v1/results/$_id': http.Response(
        jsonEncode({'ok': false, 'error': 'gone'}),
        404,
      ),
    });
    await pump(tester, client: client);

    expect(find.textContaining('expired or was removed'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('confirming "Use as my placement" pops a restore outcome', (
    tester,
  ) async {
    final client = _FakeClient({
      'GET /v1/results/$_id': http.Response(jsonEncode(_resultBody()), 200),
    });
    TransferOutcome? outcome;
    await pump(tester, client: client, onPopped: (o) => outcome = o);

    await tester.tap(find.text('Use as my placement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use it'));
    await tester.pumpAndSettle();

    expect(outcome, isNotNull);
    expect(outcome!.fromLink, isTrue);
    expect(outcome!.payload.issueScores['taxes'], -40);
    // The embedded transfer code restores the full payload, state included.
    expect(outcome!.payload.homeStateCode, 'MI');
  });

  testWidgets('an encrypted link asks for the password and opens locally', (
    tester,
  ) async {
    final envelope = await tester.runAsync(
      () => ResultEnvelope.seal(
        payload: _resultBody(),
        password: 'correct horse',
        iterations: 1000,
      ),
    );
    final client = _FakeClient({
      'GET /v1/results/$_id': http.Response(
        jsonEncode({
          'ok': true,
          'id': _id,
          'encrypted': true,
          'envelope': envelope!.toJson(),
        }),
        200,
      ),
    });
    await pump(tester, client: client);

    expect(find.text('Password for this link'), findsOneWidget);

    // Wrong password: error text, zero additional requests.
    await tester.enterText(find.byType(TextField).first, 'wrong password');
    await tapWithCrypto(tester, find.text('Open'));
    expect(find.text('That password is not right.'), findsOneWidget);
    expect(client.requests.length, 1);

    await tester.enterText(find.byType(TextField).first, 'correct horse');
    await tapWithCrypto(tester, find.text('Open'));
    expect(find.text('Strongly liberal'), findsOneWidget);
    expect(client.requests.length, 1);
  });
}
