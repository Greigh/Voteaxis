import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/models/app_settings.dart';
import 'package:voteaxis/models/politician.dart';
import 'package:voteaxis/models/quiz_bank.dart';
import 'package:voteaxis/models/scoring.dart';
import 'package:voteaxis/services/transfer_code.dart';

TransferPayload _payload({
  AppSettings settings = const AppSettings(),
  String? homeState = 'MI',
  DateTime? takenAt,
  bool handSet = false,
}) {
  return TransferPayload(
    issueScores: const {
      'taxes': -60,
      'climate': -82,
      'immigration': 14,
      'military': 100,
      'jobs': -100,
    },
    issueWeights: const {'taxes': 2.5, 'climate': 1.0, 'immigration': 0.25},
    dealbreakerIssueIds: const ['climate', 'taxes'],
    takenAt: takenAt,
    handSet: handSet,
    homeStateCode: homeState,
    settings: settings,
  );
}

void main() {
  group('issue catalog', () {
    test('covers every id in issues.json, in a frozen order', () {
      final raw = File('assets/data/issues.json').readAsStringSync();
      final ids = (jsonDecode(raw) as List<dynamic>)
          .map((e) => (e as Map<String, dynamic>)['id'] as String)
          .toList();

      // Reordering or removing an entry silently corrupts every code already
      // in the wild, so this is a hard equality on the shared prefix.
      expect(
        TransferCode.issueCatalog.take(ids.length),
        ids,
        reason: 'transferIssueCatalog is append-only — never reorder it.',
      );
      expect(
        ids.toSet().difference(TransferCode.issueCatalog.toSet()),
        isEmpty,
        reason: 'a new issue id must be appended to the catalog.',
      );
    });
  });

  group('round trip', () {
    test('scores, weights, dealbreakers, and state survive', () {
      final code = TransferCode.encode(_payload());
      final decoded = TransferCode.decode(code)!;

      expect(decoded.issueScores['taxes'], -60);
      expect(decoded.issueScores['climate'], -82);
      expect(decoded.issueScores['immigration'], 14);
      expect(decoded.issueScores['military'], 100);
      expect(decoded.issueScores['jobs'], -100);
      expect(decoded.issueWeights['taxes'], 2.5);
      expect(decoded.issueWeights['immigration'], 0.25);
      expect(decoded.dealbreakerIssueIds, containsAll(['climate', 'taxes']));
      expect(decoded.homeStateCode, 'MI');
      expect(decoded.hasProfile, isTrue);
    });

    test('every setting survives', () {
      const settings = AppSettings(
        figureFloor: FigureFloor.year1960,
        timeBlind: true,
        skipQuiz: true,
        quizLength: 40,
        dealbreakerPrompts: false,
        haptics: false,
        reduceMotion: true,
        issueWidget: false,
      );
      final decoded = TransferCode.decode(
        TransferCode.encode(_payload(settings: settings)),
      )!;
      expect(decoded.settings, settings);
    });

    test('defaults survive a round trip unchanged', () {
      final decoded = TransferCode.decode(TransferCode.encode(_payload()))!;
      expect(decoded.settings, const AppSettings());
    });

    test('time-blind is dropped when the floor cannot show it', () {
      const settings = AppSettings(
        figureFloor: FigureFloor.year2000,
        timeBlind: true,
      );
      final decoded = TransferCode.decode(
        TransferCode.encode(_payload(settings: settings)),
      )!;
      expect(decoded.settings.timeBlind, isFalse);
    });

    test('the hand-set flag and the timestamp survive', () {
      final takenAt = DateTime.utc(2026, 3, 14, 9, 26);
      final decoded = TransferCode.decode(
        TransferCode.encode(_payload(takenAt: takenAt, handSet: true)),
      )!;
      expect(decoded.handSet, isTrue);
      // Quantized to whole minutes.
      expect(decoded.takenAt, takenAt);
    });

    test('a settings-only payload carries no profile', () {
      final code = TransferCode.encode(
        const TransferPayload(homeStateCode: 'CA'),
      );
      final decoded = TransferCode.decode(code)!;
      expect(decoded.hasProfile, isFalse);
      expect(decoded.homeStateCode, 'CA');
    });

    test('an absent home state stays absent', () {
      final decoded = TransferCode.decode(
        TransferCode.encode(_payload(homeState: null)),
      )!;
      expect(decoded.homeStateCode, isNull);
    });

    test('an unknown quiz length falls back to the default', () {
      final decoded = TransferCode.decode(
        TransferCode.encode(
          _payload(settings: const AppSettings(quizLength: 7)),
        ),
      )!;
      expect(decoded.settings.quizLength, QuizBank.defaultLength);
    });

    test(
      'ids outside the catalog are dropped rather than corrupting the code',
      () {
        final code = TransferCode.encode(
          const TransferPayload(
            issueScores: {'taxes': 10, 'not_an_issue': -50},
          ),
        );
        final decoded = TransferCode.decode(code)!;
        expect(decoded.issueScores.keys, ['taxes']);
      },
    );
  });

  group('code shape', () {
    test('is prefixed, grouped, and short enough to paste', () {
      final code = TransferCode.encode(_payload());
      expect(code.startsWith(TransferCode.prefix), isTrue);
      expect(code.contains('-'), isTrue);
      expect(code.replaceAll('-', '').length, lessThan(200));
    });

    test('reads back through whitespace, case, and Crockford look-alikes', () {
      final code = TransferCode.encode(_payload());
      final mangled = '  ${code.toLowerCase().replaceAll('-', ' ')}  ';
      expect(TransferCode.decode(mangled)?.homeStateCode, 'MI');
    });

    test('a corrupted body fails the checksum instead of decoding garbage', () {
      final code = TransferCode.encode(_payload()).replaceAll('-', '');
      // Flip one character in the middle of the body.
      final middle = code.length ~/ 2;
      final swapped = code[middle] == 'A' ? 'B' : 'A';
      final broken =
          code.substring(0, middle) + swapped + code.substring(middle + 1);
      expect(TransferCode.decode(broken), isNull);
    });

    test('a truncated code fails rather than half-restoring', () {
      final code = TransferCode.encode(_payload()).replaceAll('-', '');
      expect(TransferCode.decode(code.substring(0, code.length - 6)), isNull);
    });

    test('rejects text that is not ours', () {
      expect(TransferCode.decode(''), isNull);
      expect(TransferCode.decode('hello there'), isNull);
      expect(TransferCode.decode('VX1'), isNull);
      expect(TransferCode.looksLikeCode('hello'), isFalse);
      expect(
        TransferCode.looksLikeCode(TransferCode.encode(_payload())),
        isTrue,
      );
    });

    test('a pathologically long input is rejected before it is decoded', () {
      // A hostile QR or voteaxis://restore?d=… deep link should not be able to
      // make the base-32 reader and CRC walk megabytes.
      final huge = 'VX1${'A' * 200000}';
      expect(TransferCode.decode(huge), isNull);
      expect(TransferCode.looksLikeCode(huge), isFalse);
      expect(TransferCode.codeFromLink('voteaxis://restore?d=$huge'), isNull);
    });
  });

  group('deep link', () {
    test('wraps and unwraps a code', () {
      final code = TransferCode.encode(_payload());
      final link = TransferCode.link(code);
      expect(link.startsWith('voteaxis://restore?d='), isTrue);
      expect(link.contains('-'), isFalse);
      expect(TransferCode.decode(link)?.homeStateCode, 'MI');
    });

    test('ignores links that are not ours', () {
      expect(TransferCode.codeFromLink('voteaxis://sync?code=A2B3C4'), isNull);
      expect(
        TransferCode.codeFromLink('https://example.com/?d=VX1AAAA'),
        isNull,
      );
      expect(TransferCode.codeFromLink('not a uri at all'), isNull);
    });
  });

  test('fromProfile carries the profile through unchanged', () {
    const profile = SpectrumProfile(
      issueScores: {'taxes': -30},
      pillarScores: {'economy': -30},
      axisScore: -30,
      issueWeights: {'taxes': 1.75},
      dealbreakerIssueIds: ['taxes'],
    );
    final decoded = TransferCode.decode(
      TransferCode.encode(
        TransferPayload.fromProfile(
          profile: profile,
          settings: const AppSettings(),
          homeStateCode: 'TX',
        ),
      ),
    )!;
    expect(decoded.issueScores['taxes'], -30);
    expect(decoded.issueWeights['taxes'], 1.75);
    expect(decoded.dealbreakerIssueIds, ['taxes']);
    expect(decoded.homeStateCode, 'TX');
  });
}
