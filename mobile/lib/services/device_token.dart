import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

String _hexEncode(List<int> bytes) {
  final buffer = StringBuffer();
  for (final b in bytes) {
    buffer.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

Uint8List _hexDecode(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

final _random = Random.secure();

String _randomHex(int bytes) => _hexEncode(
  List<int>.generate(bytes, (_) => _random.nextInt(256)),
);

/// The four headers a signed `/v1/politicians` request sends. See
/// `verifyDeviceSignature` in server/src/app.ts for what the server checks.
class DeviceAuthHeaders {
  const DeviceAuthHeaders({
    required this.deviceId,
    required this.timestamp,
    required this.nonce,
    required this.signatureHex,
  });

  final String deviceId;
  final int timestamp;
  final String nonce;
  final String signatureHex;

  Map<String, String> toHeaders() => {
    'x-voteaxis-device-id': deviceId,
    'x-voteaxis-timestamp': '$timestamp',
    'x-voteaxis-nonce': nonce,
    'x-voteaxis-signature': signatureHex,
  };
}

/// This install's identity for the `POLITICIANS_ALLOW_DEVICE_TOKENS` gate on
/// `/v1/politicians` (see server/README.md).
///
/// Unlike a bearer token, the credential here is a keypair: [_ensureKeyPair]
/// generates an Ed25519 keypair once and keeps the private key in secure
/// storage for the life of the install — it is never sent anywhere, not even
/// during registration, which hands the server only the public half. Every
/// request is signed fresh with [sign], so there is no static value in this
/// class, on the wire, or (if someone decompiled the app) in the binary that
/// by itself unlocks the roster. See the doc comment on
/// `AppOptions.politiciansAllowDeviceTokens` in server/src/app.ts for what
/// this scheme does and does not prove about the caller.
///
/// This class never throws. A platform-channel failure just means the next
/// roster refresh registers again instead of reusing an identity — no
/// different from a fresh install.
class DeviceIdentity {
  DeviceIdentity({FlutterSecureStorage? secureStorage})
    : _secure =
          secureStorage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _secure;
  static const _seedKey = 'politicians_device_seed_v1';
  static const _idKey = 'politicians_device_id_v1';
  static final _algorithm = Ed25519();

  Future<String?> _readSecure(String key) async {
    try {
      final value = await _secure.read(key: key);
      return (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSecure(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
    } catch (_) {
      // Best-effort — see class doc comment.
    }
  }

  /// The deviceId the server assigned, or null before [ensureRegistered] has
  /// ever succeeded.
  Future<String?> deviceId() => _readSecure(_idKey);

  Future<SimpleKeyPair?> _ensureKeyPair() async {
    try {
      final existingSeed = await _readSecure(_seedKey);
      if (existingSeed != null) {
        return await _algorithm.newKeyPairFromSeed(_hexDecode(existingSeed));
      }
      final keyPair = await _algorithm.newKeyPair();
      final seed = await keyPair.extractPrivateKeyBytes();
      await _writeSecure(_seedKey, _hexEncode(seed));
      return keyPair;
    } catch (_) {
      return null;
    }
  }

  /// Registers this install's public key if it hasn't already, via [register]
  /// (typically `VoteaxisApi.registerDevice`). Returns the deviceId — the
  /// already-stored one if this install has registered before, so a real
  /// caller pays the network round trip at most once per install, not once
  /// per refresh. Returns null if generating a keypair or the registration
  /// call itself fails; the caller keeps going without device auth for this
  /// attempt and tries again next time.
  Future<String?> ensureRegistered(
    Future<String?> Function(String publicKeyHex) register,
  ) async {
    final existing = await deviceId();
    if (existing != null) return existing;
    try {
      final keyPair = await _ensureKeyPair();
      if (keyPair == null) return null;
      final publicKey = await keyPair.extractPublicKey();
      final id = await register(_hexEncode(publicKey.bytes));
      if (id == null) return null;
      await _writeSecure(_idKey, id);
      return id;
    } catch (_) {
      return null;
    }
  }

  /// Signs a `[method] [path]` request as this device, or null if this
  /// install has not registered yet — call [ensureRegistered] first. A fresh
  /// timestamp and nonce are generated on every call, so no two calls ever
  /// produce headers a server would accept twice.
  Future<DeviceAuthHeaders?> sign({
    required String method,
    required String path,
  }) async {
    final id = await deviceId();
    if (id == null) return null;
    try {
      final keyPair = await _ensureKeyPair();
      if (keyPair == null) return null;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final nonce = _randomHex(16);
      final message = utf8.encode('$method\n$path\n$id\n$timestamp\n$nonce');
      final signature = await _algorithm.sign(message, keyPair: keyPair);
      return DeviceAuthHeaders(
        deviceId: id,
        timestamp: timestamp,
        nonce: nonce,
        signatureHex: _hexEncode(signature.bytes),
      );
    } catch (_) {
      return null;
    }
  }
}
