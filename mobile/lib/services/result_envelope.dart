import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// End-to-end encryption for password-protected share links.
///
/// A password-protected result is sealed on this device and only ever reaches
/// the server as ciphertext, so a Voteaxis operator, a database backup, and
/// anyone who scrapes the link all see the same thing: nothing. The password
/// is never sent anywhere — the reader derives the same key and the AES-GCM
/// tag is what proves they got it right.
///
/// The parameters below are a wire format shared with the web reader in
/// `web/lib/envelope.ts`. Changing any of them means bumping [version] and
/// keeping the old branch alive, or every link already shared goes dark.
class ResultEnvelope {
  const ResultEnvelope({
    required this.salt,
    required this.nonce,
    required this.ciphertext,
    this.iterations = defaultIterations,
  });

  static const version = 1;
  static const kdf = 'pbkdf2-sha256';

  /// PBKDF2-HMAC-SHA256 rounds. High enough to make an offline guess expensive,
  /// low enough that unlocking on a mid-range phone stays under a couple of
  /// seconds — the reader pays this cost on a spinner, once.
  static const defaultIterations = 210000;

  /// Lower and upper bounds on the iteration count [fromJson] will accept. The
  /// reader runs this many rounds on their own device with no say in the
  /// number, so the ceiling protects them, not the author. Matches
  /// web/lib/envelope.ts (MAX_ITERATIONS) and server/src/results.ts.
  static const minIterations = 1000;
  static const maxIterations = 600000;

  static const saltLength = 16;
  static const nonceLength = 12;
  static const _macLength = 16;

  /// The link is only as strong as the password now that guessing happens
  /// offline, so this is well above the 4 a server-side check could live with.
  static const minPasswordLength = 8;

  final Uint8List salt;
  final Uint8List nonce;

  /// Ciphertext with the 16-byte GCM tag appended, matching what WebCrypto's
  /// `crypto.subtle.encrypt` produces so the browser can read it directly.
  final Uint8List ciphertext;
  final int iterations;

  static final _cipher = AesGcm.with256bits();
  static final _random = Random.secure();

  Map<String, dynamic> toJson() => {
    'v': version,
    'kdf': kdf,
    'iterations': iterations,
    'salt': base64Encode(salt),
    'nonce': base64Encode(nonce),
    'ciphertext': base64Encode(ciphertext),
  };

  /// Returns null for anything that is not an envelope this build can open.
  static ResultEnvelope? fromJson(Map<String, dynamic> json) {
    try {
      if ((json['v'] as num?)?.toInt() != version) return null;
      if (json['kdf'] != kdf) return null;
      final iterations = (json['iterations'] as num?)?.toInt();
      if (iterations == null ||
          iterations < minIterations ||
          iterations > maxIterations) {
        return null;
      }
      final salt = base64Decode(json['salt'] as String);
      final nonce = base64Decode(json['nonce'] as String);
      final ciphertext = base64Decode(json['ciphertext'] as String);
      if (salt.length != saltLength) return null;
      if (nonce.length != nonceLength) return null;
      if (ciphertext.length <= _macLength) return null;
      return ResultEnvelope(
        salt: salt,
        nonce: nonce,
        ciphertext: ciphertext,
        iterations: iterations,
      );
    } catch (_) {
      return null;
    }
  }

  /// Stretching the password is deliberately expensive — hundreds of
  /// milliseconds on a desktop and multiples of that on a phone — so it runs
  /// on a background isolate. On the UI thread it would freeze the frame, and
  /// under `testWidgets`' fake clock it would not complete at all.
  static Future<SecretKey> _deriveKey(
    String password,
    List<int> salt,
    int iterations,
  ) async {
    final bytes = await compute(
      _stretchPassword,
      _KdfRequest(
        password: password,
        salt: Uint8List.fromList(salt),
        iterations: iterations,
      ),
    );
    return SecretKey(bytes);
  }

  static Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  /// Seals [payload] under [password]. Runs the KDF, so call it off the paint
  /// path with something on screen.
  static Future<ResultEnvelope> seal({
    required Map<String, dynamic> payload,
    required String password,
    int iterations = defaultIterations,
  }) async {
    final salt = _randomBytes(saltLength);
    final nonce = _randomBytes(nonceLength);
    final key = await _deriveKey(password, salt, iterations);
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
      nonce: nonce,
    );
    return ResultEnvelope(
      salt: salt,
      nonce: nonce,
      // WebCrypto expects the tag trailing the ciphertext.
      ciphertext: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
      iterations: iterations,
    );
  }

  /// Returns null when the password is wrong — a bad key fails the GCM tag,
  /// which is the only "is this right?" check that exists.
  Future<Map<String, dynamic>?> open(String password) async {
    try {
      final key = await _deriveKey(password, salt, iterations);
      final split = ciphertext.length - _macLength;
      final plain = await _cipher.decrypt(
        SecretBox(
          ciphertext.sublist(0, split),
          nonce: nonce,
          mac: Mac(ciphertext.sublist(split)),
        ),
        secretKey: key,
      );
      final decoded = jsonDecode(utf8.decode(plain));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

class _KdfRequest {
  const _KdfRequest({
    required this.password,
    required this.salt,
    required this.iterations,
  });

  final String password;
  final Uint8List salt;
  final int iterations;
}

/// Runs on a background isolate, so it has to be a top-level function.
Future<Uint8List> _stretchPassword(_KdfRequest request) async {
  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: request.iterations,
    bits: 256,
  ).deriveKeyFromPassword(password: request.password, nonce: request.salt);
  return Uint8List.fromList(await key.extractBytes());
}
