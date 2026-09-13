import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voteaxis/services/friend_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('empty store loads nothing', () async {
    expect(await FriendStore().load(), isNull);
  });

  test('save and load a friend identity', () async {
    final store = FriendStore();
    final expires = DateTime.now().add(const Duration(hours: 48));
    await store.save(
      FriendIdentity(code: 'A2B3C4', token: 'tok', expiresAt: expires),
    );
    final loaded = await store.load();
    expect(loaded?.code, 'A2B3C4');
    expect(loaded?.token, 'tok');
    expect(loaded?.isExpired, isFalse);
  });

  test('expired identity is still loadable', () async {
    final store = FriendStore();
    await store.save(
      FriendIdentity(
        code: 'OLDOLD',
        token: 'tok',
        expiresAt: DateTime.fromMillisecondsSinceEpoch(1),
      ),
    );
    final loaded = await store.load();
    expect(loaded?.isExpired, isTrue);
  });

  test('migrates plaintext tokens into secure storage', () async {
    SharedPreferences.setMockInitialValues({
      'friend_code_v1': 'A2B3C4',
      'friend_token_v1': 'legacy-tok',
      'friend_expires_v1': 1,
    });
    final store = FriendStore();
    final loaded = await store.load();
    expect(loaded?.code, 'A2B3C4');
    expect(loaded?.token, 'legacy-tok');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('friend_code_v1'), isNull);
    expect(prefs.getString('friend_token_v1'), isNull);
    expect(prefs.getInt('friend_expires_v1'), isNull);
    expect((await store.load())?.token, 'legacy-tok');
  });
}
