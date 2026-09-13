import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a network-refreshed copy of the roster on disk, plus the ETag
/// that produced it.
///
/// [AppData.load] always has the bundled `assets/data/politicians.json` to
/// fall back on, so a missing or unreadable cache is never fatal — it just
/// means the next launch uses whatever shipped with the app, same as before
/// this cache existed. This class never throws; every method degrades to a
/// no-op (write) or `null` (read) rather than surface a platform-channel or
/// disk error to the caller.
class PoliticiansCache {
  PoliticiansCache({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const _etagKey = 'politicians_cache_etag';
  static const _fileName = 'politicians_cache.json';

  Future<File> _file() async {
    final dir = await _directory();
    return File('${dir.path}/$_fileName');
  }

  /// The raw `politicians.json`-shaped array from the last successful fetch,
  /// or null when there isn't one yet (first launch, or every fetch since
  /// install has failed or been declined).
  Future<String?> readRaw() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      return raw.trim().isEmpty ? null : raw;
    } catch (_) {
      return null;
    }
  }

  /// The ETag that produced the cached file, sent back as `If-None-Match` so
  /// an unchanged roster answers 304 instead of re-sending ~1.5 MB.
  Future<String?> readEtag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_etagKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String raw, {String? etag}) async {
    try {
      final file = await _file();
      await file.writeAsString(raw);
    } catch (_) {
      return;
    }
    if (etag == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_etagKey, etag);
    } catch (_) {
      // The file wrote; only the ETag didn't. Next refresh just re-fetches
      // the full payload instead of getting a 304 — correct, only wasteful.
    }
  }
}
