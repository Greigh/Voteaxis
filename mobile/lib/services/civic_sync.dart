import 'dart:async';

import 'package:app_links/app_links.dart';

import 'share_link.dart';
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

/// Dispatch a resolved link to the right handler. Kept separate from
/// [listenDeepLinks] so the decision is testable without the app_links plugin.
void routeDeepLink(
  Uri? uri, {
  void Function(String code)? onSyncCode,
  void Function(String raw)? onRestoreCode,
  void Function(String id)? onResultLink,
}) {
  if (uri == null) return;
  final raw = uri.toString();

  // Shared results — a universal https link or the voteaxis://result form.
  // Hosts are constrained to the site the app publishes links on so a stray
  // "…/result/<id>" URL on another domain does not open the viewer.
  final id = ShareLink.idFrom(raw);
  if (id != null &&
      ((uri.scheme == 'https' &&
              (uri.host == 'voteaxis.org' || uri.host == 'www.voteaxis.org')) ||
          (uri.scheme == friendSyncScheme &&
              (uri.host == ShareLink.segment ||
                  uri.pathSegments.contains(ShareLink.segment))))) {
    onResultLink?.call(id);
    return;
  }

  final code = parseFriendSyncCode(raw, requireUri: true);
  if (code != null) {
    onSyncCode?.call(code);
    return;
  }
  final restore = TransferCode.codeFromLink(raw);
  if (restore != null) onRestoreCode?.call(restore);
}

/// True when [raw] repeats the link handled [window] ago or less. Pulled out
/// of [listenDeepLinks] so the app_links double-delivery guard is testable
/// without the plugin.
bool isRepeatedLink(
  String raw, {
  String? lastRaw,
  DateTime? lastAt,
  required DateTime now,
  Duration window = const Duration(seconds: 2),
}) {
  return raw == lastRaw && lastAt != null && now.difference(lastAt) < window;
}

/// Every link the app answers to: `voteaxis://sync?code=` for friend
/// compare, `voteaxis://restore?d=` for a device transfer, and shared results
/// — `voteaxis://result?id=` or the universal `https://voteaxis.org/result/<id>`.
StreamSubscription<Uri>? listenDeepLinks({
  void Function(String code)? onSyncCode,
  void Function(String raw)? onRestoreCode,
  void Function(String id)? onResultLink,
}) {
  void handle(Uri? uri) => routeDeepLink(
    uri,
    onSyncCode: onSyncCode,
    onRestoreCode: onRestoreCode,
    onResultLink: onResultLink,
  );

  try {
    final links = AppLinks();
    // app_links delivers a cold-start link twice on Android: once through
    // getInitialLink and again as the stream's first event. Without a guard
    // the router pushes the same screen twice — track the last link handled
    // and ignore an identical repeat inside a short window.
    String? lastRaw;
    DateTime? lastAt;
    void handleOnce(Uri? uri) {
      if (uri == null) return;
      final raw = uri.toString();
      final now = DateTime.now();
      if (isRepeatedLink(raw, lastRaw: lastRaw, lastAt: lastAt, now: now)) {
        return;
      }
      lastRaw = raw;
      lastAt = now;
      handle(uri);
    }

    links.getInitialLink().then(handleOnce).catchError((_) {});
    return links.uriLinkStream.listen(handleOnce, onError: (_) {});
  } catch (_) {
    return null;
  }
}
