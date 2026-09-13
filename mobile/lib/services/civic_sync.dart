import 'dart:async';

import 'package:app_links/app_links.dart';

import 'transfer_code.dart';

/// Sit-together friend sync. The API stores coordinates, not quiz answers.
const friendSyncScheme = 'voteaxis';
const friendSyncHost = 'sync';

/// Same alphabet as the Bun API (`server/src/codes.ts`).
final _codeToken = RegExp(
  r'(?:^|[^A-Z0-9])([23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6})(?:[^A-Z0-9]|$)',
);

String friendSyncPayload(String code) {
  return '$friendSyncScheme://$friendSyncHost?code=${code.toUpperCase()}';
}

String? parseFriendSyncCode(String raw, {bool requireUri = false}) {
  // A deep link or scanned payload should never be huge; cap it before the
  // URI parse and the regex scan walk it.
  if (raw.length > 4096) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri != null &&
      uri.scheme == friendSyncScheme &&
      (uri.host == friendSyncHost || uri.path == '/$friendSyncHost')) {
    final fromQuery = uri.queryParameters['code'];
    if (fromQuery != null) {
      final match = _codeToken.firstMatch(' ${fromQuery.toUpperCase()} ');
      if (match != null) return match.group(1);
    }
  }
  if (requireUri) return null;
  return _codeToken.firstMatch(trimmed.toUpperCase())?.group(1);
}

/// Every `voteaxis://` link the app answers to: `sync?code=` for friend
/// compare, `restore?d=` for a device transfer.
StreamSubscription<Uri>? listenDeepLinks({
  void Function(String code)? onSyncCode,
  void Function(String raw)? onRestoreCode,
}) {
  void handle(Uri? uri) {
    if (uri == null) return;
    final raw = uri.toString();
    final code = parseFriendSyncCode(raw, requireUri: true);
    if (code != null) {
      onSyncCode?.call(code);
      return;
    }
    final restore = TransferCode.codeFromLink(raw);
    if (restore != null) onRestoreCode?.call(restore);
  }

  try {
    final links = AppLinks();
    links.getInitialLink().then(handle).catchError((_) {});
    return links.uriLinkStream.listen(handle, onError: (_) {});
  } catch (_) {
    return null;
  }
}
