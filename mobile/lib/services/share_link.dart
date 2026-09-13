import 'dart:convert';

import '../config.dart';

/// The `voteaxis.org/result/<id>` link a placement is shared behind.
class ShareLink {
  ShareLink._();

  static const segment = 'result';

  /// Mirrors `server/src/results.ts` — lowercase, no ambiguous glyphs.
  static final _id = RegExp(r'^[23456789abcdefghjkmnpqrstuvwxyz]{16}$');

  static String urlFor(String id, {String? siteBase}) {
    final base = (siteBase ?? AppConfig.siteBase).replaceAll(RegExp(r'/$'), '');
    return '$base/$segment/$id';
  }

  /// Accepts a pasted URL, a `voteaxis://result?id=` deep link, or a bare id.
  /// Returns null for anything that is not one of those.
  static String? idFrom(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final bare = trimmed.toLowerCase();
    if (_id.hasMatch(bare)) return bare;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    final query = uri.queryParameters['id']?.toLowerCase();
    if (query != null && _id.hasMatch(query)) return query;

    final segments = uri.pathSegments;
    for (var i = 0; i < segments.length; i++) {
      if (segments[i] != segment) continue;
      if (i + 1 >= segments.length) break;
      final candidate = segments[i + 1].toLowerCase();
      if (_id.hasMatch(candidate)) return candidate;
    }
    return null;
  }
}

/// What this device published, kept so a later share reuses the same URL and
/// can still revoke it.
class StoredShareLink {
  const StoredShareLink({
    required this.id,
    required this.token,
    required this.url,
    required this.encrypted,
    required this.expiresAt,
  });

  final String id;
  final String token;
  final String url;

  /// Sealed with a password before upload, so the server cannot read it.
  final bool encrypted;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'token': token,
    'url': url,
    'encrypted': encrypted,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
  };

  static StoredShareLink? fromRaw(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final id = map['id'] as String?;
      final token = map['token'] as String?;
      final url = map['url'] as String?;
      final expires = map['expiresAt'] as num?;
      if (id == null || token == null || url == null || expires == null) {
        return null;
      }
      return StoredShareLink(
        id: id,
        token: token,
        url: url,
        encrypted: map['encrypted'] as bool? ?? false,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expires.toInt()),
      );
    } catch (_) {
      return null;
    }
  }
}
