import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/services/result_envelope.dart';

const _password = 'correct horse battery staple';

/// Real KDF cost is deliberate; the tests use a low count so they stay fast.
const _fast = 1000;

const _payload = <String, dynamic>{
  'axisScore': -42.5,
  'issueScores': {'taxes': -60.0, 'climate': -80.0},
  'pillarScores': {'economy': -55.0},
  'transferCode': 'VX1-ABCDE-FGHJK',
  'label': 'Set by hand — 2026',
};

void main() {
  group('seal and open', () {
    test('the right password returns the payload', () async {
      final envelope = await ResultEnvelope.seal(
        payload: _payload,
        password: _password,
        iterations: _fast,
      );
      expect(await envelope.open(_password), _payload);
    });

    test('the wrong password returns null rather than throwing', () async {
      final envelope = await ResultEnvelope.seal(
        payload: _payload,
        password: _password,
        iterations: _fast,
      );
      expect(await envelope.open('wrong password'), isNull);
      expect(await envelope.open(''), isNull);
    });

    test('every seal uses a fresh salt and nonce', () async {
      final a = await ResultEnvelope.seal(
        payload: _payload,
        password: _password,
        iterations: _fast,
      );
      final b = await ResultEnvelope.seal(
        payload: _payload,
        password: _password,
        iterations: _fast,
      );
      expect(a.salt, isNot(b.salt));
      expect(a.nonce, isNot(b.nonce));
      expect(a.ciphertext, isNot(b.ciphertext));
    });

    test('the ciphertext carries no plaintext', () async {
      final envelope = await ResultEnvelope.seal(
        payload: _payload,
        password: _password,
        iterations: _fast,
      );
      final wire = jsonEncode(envelope.toJson());
      expect(wire.contains('axisScore'), isFalse);
      expect(wire.contains('VX1'), isFalse);
      expect(wire.contains('taxes'), isFalse);
    });

    test('a tampered ciphertext fails the GCM tag', () async {
      final envelope = await ResultEnvelope.seal(
        payload: _payload,
        password: _password,
        iterations: _fast,
      );
      final bytes = Uint8List.fromList(envelope.ciphertext);
      bytes[0] ^= 0xFF;
      final tampered = ResultEnvelope(
        salt: envelope.salt,
        nonce: envelope.nonce,
        ciphertext: bytes,
        iterations: envelope.iterations,
      );
      expect(await tampered.open(_password), isNull);
    });

    test('a swapped salt or iteration count fails', () async {
      final envelope = await ResultEnvelope.seal(
        payload: _payload,
        password: _password,
        iterations: _fast,
      );
      final other = await ResultEnvelope.seal(
        payload: _payload,
        password: _password,
        iterations: _fast,
      );
      expect(
        await ResultEnvelope(
          salt: other.salt,
          nonce: envelope.nonce,
          ciphertext: envelope.ciphertext,
          iterations: envelope.iterations,
        ).open(_password),
        isNull,
      );
      expect(
        await ResultEnvelope(
          salt: envelope.salt,
          nonce: envelope.nonce,
          ciphertext: envelope.ciphertext,
          iterations: _fast + 1,
        ).open(_password),
        isNull,
      );
    });
  });

  group('wire format', () {
    test('round-trips through JSON', () async {
      final envelope = await ResultEnvelope.seal(
        payload: _payload,
        password: _password,
        iterations: _fast,
      );
      final back = ResultEnvelope.fromJson(
        jsonDecode(jsonEncode(envelope.toJson())) as Map<String, dynamic>,
      )!;
      expect(back.salt, envelope.salt);
      expect(back.nonce, envelope.nonce);
      expect(back.ciphertext, envelope.ciphertext);
      expect(back.iterations, envelope.iterations);
      expect(await back.open(_password), _payload);
    });

    test('declares the version and KDF the reader checks for', () async {
      final json = (await ResultEnvelope.seal(
        payload: _payload,
        password: _password,
        iterations: _fast,
      )).toJson();
      expect(json['v'], ResultEnvelope.version);
      expect(json['kdf'], ResultEnvelope.kdf);
      // Base64, because the web reader decodes it with atob.
      expect(base64Decode(json['salt'] as String), hasLength(16));
      expect(base64Decode(json['nonce'] as String), hasLength(12));
    });

    test('rejects an envelope this build cannot open', () {
      Map<String, dynamic> base() => {
        'v': ResultEnvelope.version,
        'kdf': ResultEnvelope.kdf,
        'iterations': 210000,
        'salt': base64Encode(List<int>.filled(16, 7)),
        'nonce': base64Encode(List<int>.filled(12, 7)),
        'ciphertext': base64Encode(List<int>.filled(64, 7)),
      };
      expect(ResultEnvelope.fromJson(base()), isNotNull);
      expect(ResultEnvelope.fromJson({...base(), 'v': 2}), isNull);
      expect(ResultEnvelope.fromJson({...base(), 'kdf': 'md5'}), isNull);
      expect(ResultEnvelope.fromJson({...base(), 'iterations': 10}), isNull);
      expect(
        ResultEnvelope.fromJson({...base(), 'iterations': 50000000}),
        isNull,
      );
      // The ceiling matches the web reader and the API (600k), so a phone
      // cannot be handed a link that pins it deriving a key.
      expect(
        ResultEnvelope.fromJson({
          ...base(),
          'iterations': ResultEnvelope.maxIterations + 1,
        }),
        isNull,
      );
      expect(
        ResultEnvelope.fromJson({
          ...base(),
          'iterations': ResultEnvelope.maxIterations,
        }),
        isNotNull,
      );
      expect(
        ResultEnvelope.fromJson({
          ...base(),
          'salt': base64Encode(List<int>.filled(8, 7)),
        }),
        isNull,
      );
      expect(
        ResultEnvelope.fromJson({
          ...base(),
          'nonce': base64Encode(List<int>.filled(16, 7)),
        }),
        isNull,
      );
      // A tag with no message behind it.
      expect(
        ResultEnvelope.fromJson({
          ...base(),
          'ciphertext': base64Encode(List<int>.filled(16, 7)),
        }),
        isNull,
      );
      expect(ResultEnvelope.fromJson(const {}), isNull);
      expect(
        ResultEnvelope.fromJson({...base(), 'salt': 'not base64!'}),
        isNull,
      );
    });

    test('the tag trails the ciphertext, as WebCrypto expects', () async {
      final envelope = await ResultEnvelope.seal(
        payload: const {'a': 1},
        password: _password,
        iterations: _fast,
      );
      final plaintext = utf8.encode(jsonEncode(const {'a': 1}));
      // AES-GCM is a stream cipher, so ciphertext length equals plaintext
      // length; anything past that is the 16-byte tag.
      expect(envelope.ciphertext.length, plaintext.length + 16);
    });
  });

  test('the minimum password length assumes offline guessing', () {
    expect(ResultEnvelope.minPasswordLength, greaterThanOrEqualTo(8));
  });

  test('the shipped iteration count is not accidentally lowered', () {
    expect(ResultEnvelope.defaultIterations, greaterThanOrEqualTo(210000));
  });

  group('interop with the web reader', () {
    // A share link is sealed on a phone and opened in a browser. If these two
    // implementations ever disagree, every link already out there goes dark —
    // so each side opens a fixture the other one sealed.
    Map<String, dynamic> fixture() {
      final file = File('../shared/fixtures/envelope-interop.json');
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }

    test('opens an envelope WebCrypto sealed', () async {
      final json = fixture();
      final envelope = ResultEnvelope.fromJson(
        (json['sealedByWebCrypto'] as Map).cast<String, dynamic>(),
      );
      expect(
        envelope,
        isNotNull,
        reason: 'the browser wrote an envelope this build rejects',
      );
      final opened = await envelope!.open(json['password'] as String);
      expect(opened, json['payload']);
    });

    test('the fixture this build seals is still the shipped format', () {
      final json = fixture();
      final sealed = (json['sealedByDart'] as Map).cast<String, dynamic>();
      expect(sealed['v'], ResultEnvelope.version);
      expect(sealed['kdf'], ResultEnvelope.kdf);
      expect(ResultEnvelope.fromJson(sealed), isNotNull);
    });

    test('the wrong password fails against the browser envelope too', () async {
      final json = fixture();
      final envelope = ResultEnvelope.fromJson(
        (json['sealedByWebCrypto'] as Map).cast<String, dynamic>(),
      )!;
      expect(await envelope.open('not the password'), isNull);
    });
  });
}
