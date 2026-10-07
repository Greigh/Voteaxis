import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/services/civic_sync.dart';
import 'package:voteaxis/services/transfer_code.dart';

void main() {
  test('payload is a voteaxis sync URI', () {
    expect(friendSyncPayload('a2b3c4'), 'voteaxis://sync?code=A2B3C4');
  });

  test('parses URI, bare code, and ignores lookalikes', () {
    expect(parseFriendSyncCode('voteaxis://sync?code=A2B3C4'), 'A2B3C4');
    expect(parseFriendSyncCode('A2B3C4'), 'A2B3C4');
    expect(parseFriendSyncCode('sit together: a2b3c4 please'), 'A2B3C4');
    expect(parseFriendSyncCode(''), isNull);
    expect(parseFriendSyncCode('hello'), isNull);
  });

  test('a pathologically long input is rejected before the URI parse', () {
    // A deep link or scanned payload should never be huge; the guard stops it
    // before Uri.tryParse and the regex scan walk it.
    final huge = 'voteaxis://sync?code=${'A' * 200000}';
    expect(parseFriendSyncCode(huge), isNull);
    expect(parseFriendSyncCode(huge, requireUri: true), isNull);
    expect(parseFriendSyncCode('A' * 200000), isNull);
  });

  test('QR and deep links require the voteaxis sync URI', () {
    expect(
      parseFriendSyncCode('voteaxis://sync?code=A2B3C4', requireUri: true),
      'A2B3C4',
    );
    expect(parseFriendSyncCode('A2B3C4', requireUri: true), isNull);
    expect(
      parseFriendSyncCode(
        'https://evil.example/?code=A2B3C4',
        requireUri: true,
      ),
      isNull,
    );
  });

  group('deep link routing', () {
    // listenDeepLinks needs the app_links plugin, so the routing decision it
    // makes is exercised through the two parsers it dispatches on.
    test('a sync link is a sync code and not a restore code', () {
      const link = 'voteaxis://sync?code=A2B3C4';
      expect(parseFriendSyncCode(link, requireUri: true), 'A2B3C4');
      expect(TransferCode.codeFromLink(link), isNull);
    });

    test('a restore link is a restore code and not a sync code', () {
      final code = TransferCode.encode(
        const TransferPayload(issueScores: {'taxes': -20}),
      );
      final link = TransferCode.link(code);
      expect(TransferCode.codeFromLink(link), isNotNull);
      expect(parseFriendSyncCode(link, requireUri: true), isNull);
      expect(TransferCode.decode(link)?.issueScores['taxes'], -20);
    });

    test('an unrelated link matches neither', () {
      const link = 'https://example.com/hello';
      expect(parseFriendSyncCode(link, requireUri: true), isNull);
      expect(TransferCode.codeFromLink(link), isNull);
    });

    test('an https result link routes to the viewer', () {
      String? got;
      routeDeepLink(
        Uri.parse('https://voteaxis.org/result/a2b3c4d5e6f7g8h9'),
        onResultLink: (id) => got = id,
        onSyncCode: (_) => fail('sync should not fire'),
        onRestoreCode: (_) => fail('restore should not fire'),
      );
      expect(got, 'a2b3c4d5e6f7g8h9');
    });

    test('a result link on an unrelated domain is ignored', () {
      var fired = false;
      routeDeepLink(
        Uri.parse('https://evil.example/result/a2b3c4d5e6f7g8h9'),
        onResultLink: (_) => fired = true,
      );
      expect(fired, isFalse);
    });

    test('a voteaxis://result link routes to the viewer', () {
      String? got;
      routeDeepLink(
        Uri.parse('voteaxis://result?id=A2B3C4D5E6F7G8H9'),
        onResultLink: (id) => got = id,
      );
      expect(got, 'a2b3c4d5e6f7g8h9');
    });

    test('sync and restore links still route where they did', () {
      String? code;
      routeDeepLink(
        Uri.parse('voteaxis://sync?code=A2B3C4'),
        onSyncCode: (c) => code = c,
        onResultLink: (_) => fail('result link should not fire'),
      );
      expect(code, 'A2B3C4');

      String? raw;
      final transfer = TransferCode.link(
        TransferCode.encode(const TransferPayload(issueScores: {'taxes': -20})),
      );
      routeDeepLink(
        Uri.parse(transfer),
        onRestoreCode: (r) => raw = r,
        onResultLink: (_) => fail('result link should not fire'),
      );
      expect(raw, isNotNull);
    });
  });

  group('isRepeatedLink', () {
    // app_links delivers a cold-start link twice on Android — once from
    // getInitialLink and again as the stream's first event. Without the guard
    // the router pushes the same screen twice.
    final t0 = DateTime(2026, 10, 5, 12);

    test('an identical link inside the window is a repeat', () {
      expect(
        isRepeatedLink(
          'voteaxis://result?id=abc',
          lastRaw: 'voteaxis://result?id=abc',
          lastAt: t0,
          now: t0.add(const Duration(milliseconds: 800)),
        ),
        isTrue,
      );
    });

    test('a different link inside the window is not a repeat', () {
      expect(
        isRepeatedLink(
          'voteaxis://result?id=xyz',
          lastRaw: 'voteaxis://result?id=abc',
          lastAt: t0,
          now: t0.add(const Duration(milliseconds: 800)),
        ),
        isFalse,
      );
    });

    test('the same link after the window is fresh', () {
      expect(
        isRepeatedLink(
          'voteaxis://result?id=abc',
          lastRaw: 'voteaxis://result?id=abc',
          lastAt: t0,
          now: t0.add(const Duration(seconds: 3)),
        ),
        isFalse,
      );
    });

    test('nothing handled yet means nothing can repeat', () {
      expect(isRepeatedLink('voteaxis://sync?code=A2B3C4', now: t0), isFalse);
    });
  });
}
