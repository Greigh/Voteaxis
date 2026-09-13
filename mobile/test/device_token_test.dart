import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/services/device_token.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('a fresh install has no deviceId and cannot sign', () async {
    final identity = DeviceIdentity();
    expect(await identity.deviceId(), isNull);
    expect(await identity.sign(method: 'GET', path: '/v1/politicians'), isNull);
  });

  test('ensureRegistered calls register once with a real public key and persists the id', () async {
    final identity = DeviceIdentity();
    var calls = 0;
    String? seenPublicKey;
    final id = await identity.ensureRegistered((publicKeyHex) async {
      calls++;
      seenPublicKey = publicKeyHex;
      return 'server-assigned-id';
    });
    expect(id, 'server-assigned-id');
    expect(calls, 1);
    // A raw 32-byte Ed25519 public key, hex-encoded.
    expect(seenPublicKey, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(await identity.deviceId(), 'server-assigned-id');
  });

  test('a second ensureRegistered reuses the stored id without calling register again', () async {
    final identity = DeviceIdentity();
    await identity.ensureRegistered((_) async => 'first-id');
    final calls = <String>[];
    final id = await identity.ensureRegistered((publicKeyHex) async {
      calls.add(publicKeyHex);
      return 'second-id';
    });
    expect(id, 'first-id');
    expect(calls, isEmpty);
  });

  test('a failed registration leaves the device unregistered for next time', () async {
    final identity = DeviceIdentity();
    final id = await identity.ensureRegistered((_) async => null);
    expect(id, isNull);
    expect(await identity.deviceId(), isNull);
  });

  test('sign produces a signature that verifies under the registered public key', () async {
    final identity = DeviceIdentity();
    late String publicKeyHex;
    await identity.ensureRegistered((key) async {
      publicKeyHex = key;
      return 'device-1';
    });

    final auth = await identity.sign(method: 'GET', path: '/v1/politicians');

    expect(auth, isNotNull);
    expect(auth!.deviceId, 'device-1');
    expect(auth.nonce, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(auth.signatureHex, matches(RegExp(r'^[0-9a-f]{128}$')));
    expect(
      auth.timestamp,
      closeTo(DateTime.now().millisecondsSinceEpoch, 5000),
    );

    // The server reconstructs this exact message — see verifyDeviceSignature
    // in server/src/app.ts.
    final message =
        'GET\n/v1/politicians\n${auth.deviceId}\n${auth.timestamp}\n${auth.nonce}';
    final ok = await Ed25519().verify(
      message.codeUnits,
      signature: Signature(
        List<int>.generate(
          64,
          (i) => int.parse(
            auth.signatureHex.substring(i * 2, i * 2 + 2),
            radix: 16,
          ),
        ),
        publicKey: SimplePublicKey(
          List<int>.generate(
            32,
            (i) => int.parse(
              publicKeyHex.substring(i * 2, i * 2 + 2),
              radix: 16,
            ),
          ),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    expect(ok, isTrue);
  });

  test('two signatures from the same device use different nonces and timestamps', () async {
    final identity = DeviceIdentity();
    await identity.ensureRegistered((_) async => 'device-1');
    final first = await identity.sign(method: 'GET', path: '/v1/politicians');
    final second = await identity.sign(method: 'GET', path: '/v1/politicians');
    expect(first!.nonce, isNot(second!.nonce));
    expect(first.signatureHex, isNot(second.signatureHex));
  });

  test('a second DeviceIdentity instance backed by the same storage reuses the identity', () async {
    // Simulates a second app launch: a new DeviceIdentity object, same
    // underlying secure storage, must sign as the same device without
    // re-registering.
    await DeviceIdentity().ensureRegistered((_) async => 'device-1');
    final reopened = DeviceIdentity();
    expect(await reopened.deviceId(), 'device-1');
    final auth = await reopened.sign(method: 'GET', path: '/v1/politicians');
    expect(auth?.deviceId, 'device-1');
  });
}
