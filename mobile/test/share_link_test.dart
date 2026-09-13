import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/services/share_link.dart';

const _id = 'a2b3c4d5e6f7g8h9';

void main() {
  group('idFrom', () {
    test('reads a bare id', () {
      expect(ShareLink.idFrom(_id), _id);
      expect(ShareLink.idFrom('  ${_id.toUpperCase()}  '), _id);
    });

    test('reads a pasted https URL', () {
      expect(ShareLink.idFrom('https://voteaxis.org/result/$_id'), _id);
      expect(ShareLink.idFrom('https://voteaxis.org/result/$_id?utm=x'), _id);
      expect(ShareLink.idFrom('http://localhost:3000/result/$_id'), _id);
    });

    test('reads a voteaxis:// deep link', () {
      expect(ShareLink.idFrom('voteaxis://result?id=$_id'), _id);
    });

    test('rejects anything that is not a result id', () {
      expect(ShareLink.idFrom(''), isNull);
      expect(ShareLink.idFrom('https://voteaxis.org/methodology'), isNull);
      expect(ShareLink.idFrom('https://voteaxis.org/result/short'), isNull);
      // 0, 1, i, l, o, and u are excluded from the alphabet.
      expect(
        ShareLink.idFrom('https://voteaxis.org/result/${'o' * 16}'),
        isNull,
      );
      expect(ShareLink.idFrom('VX1-ABCDE-FGHJK'), isNull);
    });
  });

  test('urlFor builds against a site base without a trailing slash', () {
    expect(
      ShareLink.urlFor(_id, siteBase: 'https://voteaxis.org/'),
      'https://voteaxis.org/result/$_id',
    );
  });

  group('StoredShareLink', () {
    test('round-trips through JSON', () {
      final link = StoredShareLink(
        id: _id,
        token: 'f' * 48,
        url: 'https://voteaxis.org/result/$_id',
        encrypted: true,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(1760000000000),
      );
      final back = StoredShareLink.fromRaw(
        '{"id":"$_id","token":"${'f' * 48}",'
        '"url":"${link.url}","encrypted":true,"expiresAt":1760000000000}',
      )!;
      expect(back.id, link.id);
      expect(back.token, link.token);
      expect(back.encrypted, isTrue);
      expect(back.expiresAt, link.expiresAt);
    });

    test('returns null for junk or a missing field', () {
      expect(StoredShareLink.fromRaw('not json'), isNull);
      expect(StoredShareLink.fromRaw('{"id":"$_id"}'), isNull);
    });

    test('knows when it has expired', () {
      final stale = StoredShareLink(
        id: _id,
        token: 'f' * 48,
        url: 'x',
        encrypted: false,
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(stale.isExpired, isTrue);
    });
  });
}
