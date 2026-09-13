import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FriendIdentity {
  const FriendIdentity({
    required this.code,
    required this.token,
    required this.expiresAt,
  });

  final String code;
  final String token;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class FriendStore {
  FriendStore({FlutterSecureStorage? secureStorage})
    : _secure =
          secureStorage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _secure;

  static const _secureKey = 'friend_identity_v1';
  static const _codeKey = 'friend_code_v1';
  static const _tokenKey = 'friend_token_v1';
  static const _expiresKey = 'friend_expires_v1';

  Future<FriendIdentity?> load() async {
    final secure = await _secure.read(key: _secureKey);
    if (secure != null && secure.isNotEmpty) {
      return _fromJson(secure);
    }
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_codeKey);
    final token = prefs.getString(_tokenKey);
    final expires = prefs.getInt(_expiresKey);
    if (code == null || token == null || expires == null) return null;
    final identity = FriendIdentity(
      code: code,
      token: token,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expires),
    );
    await save(identity);
    return identity;
  }

  Future<void> save(FriendIdentity identity) async {
    await _secure.write(
      key: _secureKey,
      value: jsonEncode({
        'code': identity.code,
        'token': identity.token,
        'expiresAt': identity.expiresAt.millisecondsSinceEpoch,
      }),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_codeKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_expiresKey);
  }

  FriendIdentity? _fromJson(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final code = map['code'] as String?;
      final token = map['token'] as String?;
      final expires = map['expiresAt'] as num?;
      if (code == null || token == null || expires == null) return null;
      return FriendIdentity(
        code: code,
        token: token,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expires.toInt()),
      );
    } catch (_) {
      return null;
    }
  }
}
