import 'rollcall_history.dart';

export 'rollcall_history.dart';

/// How far back the match list goes. Default is 2000s plus (modern day).
class FigureFloor {
  FigureFloor._();

  static const year2000 = 2000;
  static const year1980 = 1980;
  static const year1960 = 1960;
  static const allowed = [year2000, year1980, year1960];

  static const labels = {
    year2000: '2000s plus',
    year1980: '1980s plus',
    year1960: '1960s plus',
  };

  static const blurbs = {
    year2000: '21st century — sitting members, Obama, Trump, GW Bush.',
    year1980: 'Back through Reagan and the late Cold War.',
    year1960: 'Back through Kennedy, plus Progressive Era quiz wording.',
  };

  static int coerce(int? year) => allowed.contains(year) ? year! : year2000;

  /// Historical tab, ancestry, and time-blind — not the 2000s-plus default.
  static bool showsPastUi(int year) => year < year2000;

  /// 1912-style questions only on the deepest floor.
  static bool showsHistoricalQuiz(int year) => year <= year1960;
}

class SignatureStance {
  const SignatureStance({
    required this.issueId,
    required this.blurb,
    this.quote,
    this.sourceUrl,
  });

  final String issueId;
  final String blurb;
  final String? quote;
  final String? sourceUrl;

  static const genericBlurbs = {
    'District-focused economic priorities.',
    'Core contrast with the opposing nominee.',
    'Core fiscal and tax posture in the Senate.',
    'Signature contrast on health and entitlements.',
  };

  bool get isGenericPlaceholder => genericBlurbs.contains(blurb);

  factory SignatureStance.fromJson(Map<String, dynamic> json) {
    return SignatureStance(
      issueId: json['issueId'] as String,
      blurb: json['blurb'] as String,
      quote: json['quote'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
    );
  }
}

class Politician {
  const Politician({
    required this.id,
    required this.name,
    required this.role,
    required this.party,
    required this.state,
    required this.officeType,
    required this.current,
    required this.bio,
    required this.officeHistory,
    required this.issues,
    required this.confidence,
    required this.signatureStances,
    this.bioguideId,
    this.district,
    this.rollcallCounts = const {},
    this.rollcallSessions = const [],
  });

  final String id;
  final String name;
  final String role;
  final String party;
  final String state;
  final String officeType;
  final bool current;
  final String bio;
  final List<String> officeHistory;

  /// Issue id → axis score on Liberal 100 ← 0 → Conservative 100
  /// (stored internally as −100…+100 for math).
  final Map<String, double> issues;

  /// Issue id → documented | inferred | contested
  final Map<String, String> confidence;
  final List<SignatureStance> signatureStances;

  /// Biographical Directory id used to look up BICAM bill receipts.
  final String? bioguideId;

  /// U.S. House district, 1-based — at-large seats (and DC's delegate) are 1.
  /// Only meaningful on `current` representatives; former members served
  /// different lines and carry null.
  final int? district;

  /// Issue id → number of coded floor votes blended into this score.
  final Map<String, int> rollcallCounts;

  /// Floor-vote coordinates by Congress. Display only — does not rescore SII.
  final List<RollcallSession> rollcallSessions;

  bool get hasVoteRecord => rollcallSessions.length >= 2;

  factory Politician.fromJson(Map<String, dynamic> json) {
    final issuesRaw = json['issues'] as Map<String, dynamic>? ?? {};
    final confidenceRaw = json['confidence'] as Map<String, dynamic>? ?? {};
    final stancesRaw = json['signatureStances'] as List<dynamic>? ?? [];
    final historyRaw = json['officeHistory'] as List<dynamic>? ?? [];

    return Politician(
      id: json['id'] as String,
      name: json['name'] as String,
      role: json['role'] as String,
      party: json['party'] as String,
      state: (json['state'] as String?) ?? '',
      officeType: (json['officeType'] as String?) ?? 'other',
      current: (json['current'] as bool?) ?? false,
      bio: (json['bio'] as String?) ?? '',
      officeHistory: historyRaw.map((e) => e as String).toList(),
      issues: issuesRaw.map((k, v) => MapEntry(k, (v as num).toDouble())),
      confidence: confidenceRaw.map((k, v) => MapEntry(k, v as String)),
      signatureStances: stancesRaw
          .map((e) => SignatureStance.fromJson(e as Map<String, dynamic>))
          .toList(),
      bioguideId: json['bioguideId'] as String?,
      district: (json['district'] as num?)?.toInt(),
      rollcallCounts: (json['rollcallCounts'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, (v as num).toInt())),
      rollcallSessions: RollcallSession.listFrom(json['rollcallSessions']),
    );
  }

  Politician copyWith({
    Map<String, double>? issues,
    Map<String, String>? confidence,
    Map<String, int>? rollcallCounts,
    List<RollcallSession>? rollcallSessions,
  }) {
    return Politician(
      id: id,
      name: name,
      role: role,
      party: party,
      state: state,
      officeType: officeType,
      current: current,
      bio: bio,
      officeHistory: officeHistory,
      issues: issues ?? this.issues,
      confidence: confidence ?? this.confidence,
      signatureStances: signatureStances,
      bioguideId: bioguideId,
      district: district,
      rollcallCounts: rollcallCounts ?? this.rollcallCounts,
      rollcallSessions: rollcallSessions ?? this.rollcallSessions,
    );
  }

  String get initials {
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  /// Stances with a real note — not the ingest placeholders.
  List<SignatureStance> get displayStances => [
    for (final s in signatureStances)
      if (!s.isGenericPlaceholder) s,
  ];

  /// Issues whose score rests on a record or a roll-call blend, not a guess.
  int get _groundedIssues {
    var n = 0;
    for (final v in confidence.values) {
      if (v == 'documented' || v == 'rollcall') n++;
    }
    return n;
  }

  /// One-line rollup of the per-issue [confidence] map for a profile-level tag.
  ///
  /// `documented` — almost every issue rests on a public record or roll-call blend.
  /// `mixed` — a documented core, with some issues still inferred.
  /// `inferred` — the vector is largely a judgment from party and caucus alignment.
  String get profileConfidence {
    if (confidence.isEmpty) return 'inferred';
    final ratio = _groundedIssues / confidence.length;
    if (ratio >= 0.9) return 'documented';
    if (ratio < 0.25) return 'inferred';
    return 'mixed';
  }

  /// Short sentence that explains [profileConfidence] on the detail screen.
  String get profileConfidenceNote {
    switch (profileConfidence) {
      case 'documented':
        return 'Issue scores rest on a public record or coded floor votes.';
      case 'mixed':
        return 'A documented core; the rest is inferred from party and '
            'caucus alignment.';
      default:
        return _groundedIssues == 0
            ? 'Issue scores are inferred from public record and party '
                  'alignment, not itemized per issue.'
            : 'A few issues rest on their public record; the rest is '
                  'inferred from party and caucus alignment.';
    }
  }

  bool get isPresident => officeType == 'president';

  bool get isMichigan => state.toUpperCase() == 'MI';

  /// Sitting or running for an office people vote for.
  bool get isElectoralOffice {
    switch (officeType) {
      case 'governor':
      case 'senator':
      case 'representative':
      case 'state_senator':
      case 'state_representative':
        return true;
      default:
        return false;
    }
  }

  /// True if they held office in [floorYear] or later (or are currently serving).
  bool servedSince(int floorYear) {
    if (current) return true;
    final span = serviceSpan;
    if (span != null) return span.$2 >= floorYear;
    return isElectoralOffice;
  }

  bool get isModern => servedSince(FigureFloor.year2000);

  /// Role without ordinals or years — used when time-blind matching is on.
  String get eraBlindRole {
    var text = role;
    text = text.replaceAll(RegExp(r'\s*\(\d{4}[^)]*\)'), '');
    text = text.replaceAll(
      RegExp(r'\b\d+(st|nd|rd|th)\b', caseSensitive: false),
      '',
    );
    text = text.replaceAll(RegExp(r'\s+&\s+'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return party.isEmpty ? 'Political figure' : party;
    return text;
  }

  /// Years covered by officeHistory, if we can parse them.
  (int, int)? get serviceSpan {
    var minY = 9999;
    var maxY = 0;
    const now = 2026;
    final ranges = RegExp(
      r'(\d{4})\s*[\u2013\-]\s*(present|\d{4})',
      caseSensitive: false,
    );
    for (final line in officeHistory) {
      for (final match in ranges.allMatches(line)) {
        final start = int.parse(match.group(1)!);
        final endRaw = match.group(2)!.toLowerCase();
        final end = endRaw == 'present' ? now : int.parse(endRaw);
        if (start < minY) minY = start;
        if (end > maxY) maxY = end;
      }
    }
    if (maxY == 0) {
      final years = RegExp(r'\b(?:19|20)\d{2}\b');
      for (final line in officeHistory) {
        for (final match in years.allMatches(line)) {
          final y = int.parse(match.group(0)!);
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxY == 0) return null;
    return (minY, maxY);
  }

  bool servedDuring(int startYear, int endYear) {
    final span = serviceSpan;
    if (span == null) return false;
    return span.$1 <= endYear && span.$2 >= startYear;
  }
}
