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
  });
}
