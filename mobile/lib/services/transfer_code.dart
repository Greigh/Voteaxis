import 'dart:typed_data';

import '../models/app_settings.dart';
import '../models/politician.dart';
import '../models/quiz_bank.dart';
import '../models/scoring.dart';

/// Offline device-to-device transfer.
///
/// The whole placement plus every preference is packed into ~80 bytes and
/// rendered as one short Crockford base-32 code. That fits comfortably in a
/// QR, a text message, or a clipboard paste — so moving to a new phone never
/// involves a file picker, an account, or the Voteaxis server. Scores survive
/// at 1-point resolution on the -100..100 scale, which is below anything the
/// UI renders.
class TransferCode {
  TransferCode._();

  static const scheme = 'voteaxis';
  static const host = 'restore';

  /// Printed in front of every code so a stray string is obviously ours.
  static const prefix = 'VX1';

  static const _magic = 0x56; // 'V'
  static const _version = 0x01;

  /// A real code is well under 200 characters (see the "short enough to paste"
  /// test). Anything past this ceiling is not ours — reject it before decoding
  /// so a hostile QR or `voteaxis://restore?d=…` deep link cannot make the
  /// base-32 reader and CRC walk megabytes. The server enforces the same class
  /// of bound with `^VX1[-0-9A-Z]{8,400}$`.
  static const _maxInputLength = 4096;

  /// APPEND ONLY. An id's index here is baked into every code ever produced,
  /// so ids may be added at the end but never reordered or removed.
  /// `test/transfer_code_test.dart` fails if this drifts from issues.json.
  static const issueCatalog = <String>[
    'jobs',
    'taxes',
    'deficit',
    'inflation',
    'free_market',
    'welfare',
    'abortion',
    'civil_rights',
    'lgbtq',
    'education',
    'traditional_values',
    'healthcare',
    'medicare',
    'social_security',
    'crime',
    'gun_control',
    'immigration',
    'climate',
    'energy',
    'foreign_policy',
    'terrorism',
    'military',
  ];

  static final Map<String, int> _issueIndex = {
    for (var i = 0; i < issueCatalog.length; i++) issueCatalog[i]: i,
  };

  // Crockford base 32: no I, L, O, or U, so codes never turn into words and
  // never collide when read aloud.
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static String encode(TransferPayload payload) {
    final settings = payload.settings.normalized;
    final scores = <MapEntry<int, double>>[];
    for (final entry in payload.issueScores.entries) {
      final index = _issueIndex[entry.key];
      if (index != null) scores.add(MapEntry(index, entry.value));
    }
    scores.sort((a, b) => a.key.compareTo(b.key));

    final dealbreakers = <int>[
      for (final id in payload.dealbreakerIssueIds)
        if (_issueIndex[id] != null) _issueIndex[id]!,
    ]..sort();

    final state = payload.homeStateCode?.toUpperCase();
    final hasState = state != null && state.length == 2;
    final hasProfile = scores.isNotEmpty;
    final takenAt = payload.takenAt;

    var flagsA = _floorCode(settings.figureFloor) & 0x03;
    if (settings.timeBlind) flagsA |= 1 << 2;
    if (settings.skipQuiz) flagsA |= 1 << 3;
    if (settings.dealbreakerPrompts) flagsA |= 1 << 4;
    if (settings.haptics) flagsA |= 1 << 5;
    if (settings.reduceMotion) flagsA |= 1 << 6;
    if (settings.issueWidget) flagsA |= 1 << 7;

    var flagsB = _lengthCode(settings.quizLength) & 0x03;
    if (hasState) flagsB |= 1 << 2;
    if (hasProfile) flagsB |= 1 << 3;
    if (takenAt != null) flagsB |= 1 << 4;
    if (payload.handSet) flagsB |= 1 << 5;

    final bytes = <int>[_magic, _version, flagsA, flagsB];

    if (hasState) {
      bytes.addAll(state.codeUnits.take(2));
    }
    if (takenAt != null) {
      final minutes = takenAt.toUtc().millisecondsSinceEpoch ~/ 60000;
      bytes.addAll(_uint32(minutes));
    }
    if (hasProfile) {
      bytes.add(scores.length);
      for (final entry in scores) {
        bytes.add(entry.key);
        bytes.add(_quantizeScore(entry.value));
        bytes.add(
          _quantizeWeight(payload.issueWeights[issueCatalog[entry.key]]),
        );
      }
      bytes.add(dealbreakers.length);
      bytes.addAll(dealbreakers);
    }

    final crc = _crc16(bytes);
    bytes.addAll([(crc >> 8) & 0xFF, crc & 0xFF]);

    return _group('$prefix${_toBase32(bytes)}');
  }

  /// Returns null for anything that is not a well-formed, intact code.
  static TransferPayload? decode(String raw) {
    if (raw.length > _maxInputLength) return null;
    final fromLink = codeFromLink(raw);
    final cleaned = _clean(fromLink ?? raw);
    if (!cleaned.startsWith(prefix)) return null;
    final bytes = _fromBase32(cleaned.substring(prefix.length));
    if (bytes == null || bytes.length < 6) return null;

    final body = bytes.sublist(0, bytes.length - 2);
    final crc = (bytes[bytes.length - 2] << 8) | bytes[bytes.length - 1];
    if (_crc16(body) != crc) return null;
    if (body[0] != _magic || body[1] != _version) return null;

    final flagsA = body[2];
    final flagsB = body[3];
    var i = 4;

    String? homeState;
    if (flagsB & (1 << 2) != 0) {
      if (i + 2 > body.length) return null;
      homeState = String.fromCharCodes(body.sublist(i, i + 2));
      i += 2;
    }

    DateTime? takenAt;
    if (flagsB & (1 << 4) != 0) {
      if (i + 4 > body.length) return null;
      final minutes =
          (body[i] << 24) |
          (body[i + 1] << 16) |
          (body[i + 2] << 8) |
          body[i + 3];
      takenAt = DateTime.fromMillisecondsSinceEpoch(
        minutes * 60000,
        isUtc: true,
      );
      i += 4;
    }

    final issueScores = <String, double>{};
    final issueWeights = <String, double>{};
    final dealbreakers = <String>[];
    if (flagsB & (1 << 3) != 0) {
      if (i >= body.length) return null;
      final count = body[i++];
      if (i + count * 3 > body.length) return null;
      for (var n = 0; n < count; n++) {
        final index = body[i];
        final score = body[i + 1];
        final weight = body[i + 2];
        i += 3;
        // A code written by a newer build can carry ids this build has never
        // heard of. Drop them rather than failing the whole restore.
        if (index >= issueCatalog.length) continue;
        final id = issueCatalog[index];
        issueScores[id] = (score - 100).toDouble().clamp(-100.0, 100.0);
        if (weight > 0) issueWeights[id] = weight / 40.0;
      }
      if (i >= body.length) return null;
      final dealbreakerCount = body[i++];
      if (i + dealbreakerCount > body.length) return null;
      for (var n = 0; n < dealbreakerCount; n++) {
        final index = body[i++];
        if (index < issueCatalog.length) dealbreakers.add(issueCatalog[index]);
      }
    }

    return TransferPayload(
      issueScores: issueScores,
      issueWeights: issueWeights,
      dealbreakerIssueIds: dealbreakers,
      takenAt: takenAt,
      handSet: flagsB & (1 << 5) != 0,
      homeStateCode: homeState,
      settings: AppSettings(
        figureFloor: _floorFromCode(flagsA & 0x03),
        timeBlind: flagsA & (1 << 2) != 0,
        skipQuiz: flagsA & (1 << 3) != 0,
        dealbreakerPrompts: flagsA & (1 << 4) != 0,
        haptics: flagsA & (1 << 5) != 0,
        reduceMotion: flagsA & (1 << 6) != 0,
        issueWidget: flagsA & (1 << 7) != 0,
        quizLength: _lengthFromCode(flagsB & 0x03),
      ).normalized,
    );
  }

  /// Deep link a QR or a shared message carries. Opening it restores directly.
  static String link(String code) => '$scheme://$host?d=${_clean(code)}';

  static String? codeFromLink(String raw) {
    if (raw.length > _maxInputLength) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != scheme) return null;
    if (uri.host != host && uri.path != '/$host') return null;
    final data = uri.queryParameters['d'];
    if (data == null || data.isEmpty) return null;
    return data;
  }

  /// True for text that looks like ours, before the checksum is checked.
  static bool looksLikeCode(String raw) {
    if (raw.length > _maxInputLength) return false;
    final cleaned = _clean(codeFromLink(raw) ?? raw);
    return cleaned.startsWith(prefix) && cleaned.length > prefix.length + 8;
  }

  static int _floorCode(int year) => switch (year) {
    FigureFloor.year1980 => 1,
    FigureFloor.year1960 => 2,
    _ => 0,
  };

  static int _floorFromCode(int code) => switch (code) {
    1 => FigureFloor.year1980,
    2 => FigureFloor.year1960,
    _ => FigureFloor.year2000,
  };

  static int _lengthCode(int length) {
    final index = QuizBank.lengthOptions.indexOf(length);
    return index < 0
        ? QuizBank.lengthOptions.indexOf(QuizBank.defaultLength)
        : index;
  }

  static int _lengthFromCode(int code) => code < QuizBank.lengthOptions.length
      ? QuizBank.lengthOptions[code]
      : QuizBank.defaultLength;

  static int _quantizeScore(double score) =>
      (score.clamp(-100.0, 100.0) + 100).round().clamp(0, 200);

  /// 0 means "no weight recorded" — a real importance weight is never below
  /// 0.25, which quantizes to 10.
  static int _quantizeWeight(double? weight) =>
      weight == null ? 0 : (weight * 40).round().clamp(1, 255);

  static List<int> _uint32(int value) => [
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];

  static String _toBase32(List<int> bytes) {
    final buffer = StringBuffer();
    var bits = 0;
    var acc = 0;
    for (final byte in bytes) {
      acc = (acc << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        buffer.write(_alphabet[(acc >> (bits - 5)) & 0x1F]);
        bits -= 5;
      }
    }
    if (bits > 0) {
      buffer.write(_alphabet[(acc << (5 - bits)) & 0x1F]);
    }
    return buffer.toString();
  }

  static Uint8List? _fromBase32(String input) {
    final bytes = <int>[];
    var bits = 0;
    var acc = 0;
    for (final char in input.split('')) {
      final value = _alphabet.indexOf(char);
      if (value < 0) return null;
      acc = (acc << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bytes.add((acc >> (bits - 8)) & 0xFF);
        bits -= 8;
      }
    }
    return Uint8List.fromList(bytes);
  }

  /// Uppercases, drops separators, and folds the Crockford look-alikes so a
  /// hand-typed or auto-corrected code still lands.
  static String _clean(String raw) {
    final buffer = StringBuffer();
    for (final char in raw.trim().toUpperCase().split('')) {
      switch (char) {
        case 'O':
          buffer.write('0');
        case 'I':
        case 'L':
          buffer.write('1');
        case 'U':
          buffer.write('V');
        default:
          if (RegExp(r'[0-9A-Z]').hasMatch(char)) buffer.write(char);
      }
    }
    return buffer.toString();
  }

  /// Dashes every 5 characters — the difference between a wall of glyphs and
  /// something a person will actually read back over the phone.
  static String _group(String code) {
    final chunks = <String>[];
    for (var i = 0; i < code.length; i += 5) {
      chunks.add(code.substring(i, i + 5 > code.length ? code.length : i + 5));
    }
    return chunks.join('-');
  }

  static int _crc16(List<int> bytes) {
    var crc = 0xFFFF;
    for (final byte in bytes) {
      crc ^= byte << 8;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
        crc &= 0xFFFF;
      }
    }
    return crc;
  }
}

/// Everything one code carries.
class TransferPayload {
  const TransferPayload({
    this.issueScores = const {},
    this.issueWeights = const {},
    this.dealbreakerIssueIds = const [],
    this.takenAt,
    this.handSet = false,
    this.homeStateCode,
    this.settings = const AppSettings(),
  });

  final Map<String, double> issueScores;
  final Map<String, double> issueWeights;
  final List<String> dealbreakerIssueIds;
  final DateTime? takenAt;

  /// The placement came from the hand-set screen, not a quiz run.
  final bool handSet;
  final String? homeStateCode;
  final AppSettings settings;

  bool get hasProfile => issueScores.isNotEmpty;

  factory TransferPayload.fromProfile({
    required SpectrumProfile profile,
    required AppSettings settings,
    String? homeStateCode,
    DateTime? takenAt,
    bool handSet = false,
  }) {
    return TransferPayload(
      issueScores: profile.issueScores,
      issueWeights: profile.issueWeights,
      dealbreakerIssueIds: profile.dealbreakerIssueIds,
      takenAt: takenAt,
      handSet: handSet,
      homeStateCode: homeStateCode,
      settings: settings,
    );
  }
}
