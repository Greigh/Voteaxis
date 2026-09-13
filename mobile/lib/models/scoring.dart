import 'issue.dart';
import 'politician.dart';
import 'question.dart';

class IssueOverlap {
  const IssueOverlap({
    required this.issueId,
    required this.diff,
    required this.userScore,
    required this.politicianScore,
  });

  final String issueId;
  final double diff;
  final double userScore;
  final double politicianScore;
}

class MatchResult {
  const MatchResult({
    required this.politician,
    required this.distance,
    required this.closeness,
    required this.agreements,
    required this.disagreements,
    required this.axisScore,
    this.dealbreakerHits = const [],
  });

  final Politician politician;
  final double distance;
  final int closeness;
  final List<IssueOverlap> agreements;
  final List<IssueOverlap> disagreements;
  final double axisScore;
  final List<String> dealbreakerHits;

  bool get hasDealbreaker => dealbreakerHits.isNotEmpty;
}

class CivicVenn {
  const CivicVenn({
    required this.aligned,
    required this.youMoreLiberal,
    required this.theyMoreLiberal,
  });

  final List<IssueOverlap> aligned;
  final List<IssueOverlap> youMoreLiberal;
  final List<IssueOverlap> theyMoreLiberal;
}

class SpectrumProfile {
  const SpectrumProfile({
    required this.issueScores,
    required this.pillarScores,
    required this.axisScore,
    this.issueWeights = const {},
    this.dealbreakerIssueIds = const [],
  });

  final Map<String, double> issueScores;
  final Map<String, double> pillarScores;
  final double axisScore;

  /// Issue id → how much that issue should pull axis and matching (1.0 = average).
  final Map<String, double> issueWeights;
  final List<String> dealbreakerIssueIds;
}

/// Likert answer: -2 (strongly disagree) … +2 (strongly agree).
class Scoring {
  Scoring._();

  static const likertLabels = <String>[
    'Strongly disagree',
    'Disagree',
    'Neutral',
    'Agree',
    'Strongly agree',
  ];

  static const importanceLabels = <String>[
    'Low',
    'Somewhat',
    'Average',
    'High',
    'Essential',
  ];

  /// Multipliers for the five importance stops (index 2 = Average).
  static const importanceWeights = <double>[0.25, 0.5, 1.0, 1.75, 2.5];

  static const defaultImportanceIndex = 2;
  static const maxDealbreakers = 3;
  static const dealbreakerDiff = 70.0;
  static const rollcallMinVotes = 3;
  static const rollcallPrior = 6;
  static const microCalibrationWeight = 0.2;

  /// |issue score| at or above this is a hard lean (Agree or stronger).
  static const steelManAbsScore = 50.0;

  /// Shared-issue gap below this counts as aligned on the civic Venn.
  static const vennAlignMaxDiff = 35.0;

  static int likertValue(int index) => index - 2;

  static double importanceWeight(int index) {
    final i = index.clamp(0, importanceWeights.length - 1);
    return importanceWeights[i];
  }

  static double contribution({
    required int likertIndex,
    required int polarity,
  }) {
    return likertValue(likertIndex) * polarity * 50.0;
  }

  /// Weighted issue scores from quiz answers.
  static Map<String, double> issueScoresFromAnswers({
    required List<Question> questions,
    required List<int> likertIndexes,
    List<int>? importanceIndexes,
  }) {
    assert(questions.length == likertIndexes.length);
    final sums = <String, double>{};
    final weights = <String, double>{};

    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      final value = contribution(
        likertIndex: likertIndexes[i],
        polarity: q.polarity,
      );
      final w = importanceWeight(
        importanceIndexes == null
            ? defaultImportanceIndex
            : importanceIndexes[i],
      );
      sums[q.issueId] = (sums[q.issueId] ?? 0) + value * w;
      weights[q.issueId] = (weights[q.issueId] ?? 0) + w;
    }

    return {for (final id in sums.keys) id: sums[id]! / weights[id]!};
  }

  /// Average importance per issue (so two questions on one issue don't double-count).
  static Map<String, double> issueWeightsFromAnswers({
    required List<Question> questions,
    List<int>? importanceIndexes,
  }) {
    final sums = <String, double>{};
    final counts = <String, int>{};
    for (var i = 0; i < questions.length; i++) {
      final id = questions[i].issueId;
      final w = importanceWeight(
        importanceIndexes == null
            ? defaultImportanceIndex
            : importanceIndexes[i],
      );
      sums[id] = (sums[id] ?? 0) + w;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return {for (final id in sums.keys) id: sums[id]! / counts[id]!};
  }

  static Map<String, double> pillarScoresFromIssues({
    required Map<String, double> issueScores,
    required List<Issue> issues,
    Map<String, double>? issueWeights,
  }) {
    final sums = <String, double>{};
    final weights = <String, double>{};
    for (final issue in issues) {
      final score = issueScores[issue.id];
      if (score == null) continue;
      final w = issueWeights?[issue.id] ?? 1.0;
      if (w <= 0) continue;
      sums[issue.pillarId] = (sums[issue.pillarId] ?? 0) + score * w;
      weights[issue.pillarId] = (weights[issue.pillarId] ?? 0) + w;
    }

    return {for (final id in sums.keys) id: sums[id]! / weights[id]!};
  }

  static double axisFromIssueScores(
    Map<String, double> issueScores, [
    Map<String, double>? issueWeights,
  ]) {
    if (issueScores.isEmpty) return 0;
    var weightedSum = 0.0;
    var weightTotal = 0.0;
    for (final entry in issueScores.entries) {
      final w = issueWeights?[entry.key] ?? 1.0;
      if (w <= 0) continue;
      weightedSum += entry.value * w;
      weightTotal += w;
    }
    if (weightTotal == 0) return 0;
    return (weightedSum / weightTotal).clamp(-100.0, 100.0);
  }

  static double axisFromPillars(
    Map<String, double> pillarScores, [
    Map<String, double>? weights,
  ]) {
    if (pillarScores.isEmpty) return 0;
    var weightedSum = 0.0;
    var weightTotal = 0.0;
    for (final entry in pillarScores.entries) {
      final w = weights?[entry.key] ?? 1.0;
      if (w <= 0) continue;
      weightedSum += entry.value * w;
      weightTotal += w;
    }
    if (weightTotal == 0) return 0;
    return (weightedSum / weightTotal).clamp(-100.0, 100.0);
  }

  static SpectrumProfile profileFromIssueScores({
    required Map<String, double> issueScores,
    required List<Issue> issues,
    Map<String, double>? issueWeights,
    List<String> dealbreakerIssueIds = const [],
  }) {
    final pillars = pillarScoresFromIssues(
      issueScores: issueScores,
      issues: issues,
      issueWeights: issueWeights,
    );
    return SpectrumProfile(
      issueScores: issueScores,
      pillarScores: pillars,
      axisScore: axisFromIssueScores(issueScores, issueWeights),
      issueWeights: issueWeights ?? const {},
      dealbreakerIssueIds: dealbreakerIssueIds,
    );
  }

  static SpectrumProfile profileFromAnswers({
    required List<Question> questions,
    required List<int> likertIndexes,
    required List<Issue> issues,
    List<int>? importanceIndexes,
    List<String> dealbreakerIssueIds = const [],
  }) {
    final issueScores = issueScoresFromAnswers(
      questions: questions,
      likertIndexes: likertIndexes,
      importanceIndexes: importanceIndexes,
    );
    final issueWeights = issueWeightsFromAnswers(
      questions: questions,
      importanceIndexes: importanceIndexes,
    );
    return profileFromIssueScores(
      issueScores: issueScores,
      issues: issues,
      issueWeights: issueWeights,
      dealbreakerIssueIds: dealbreakerIssueIds,
    );
  }

  /// Expand a hand-set pillar placement into per-issue scores so a manual
  /// level ranks and compares exactly like a quiz run.
  static SpectrumProfile profileFromPillarScores({
    required Map<String, double> pillarScores,
    required List<Issue> issues,
    List<String> dealbreakerIssueIds = const [],
  }) {
    final issueScores = <String, double>{};
    for (final issue in issues) {
      final score = pillarScores[issue.pillarId];
      if (score == null) continue;
      issueScores[issue.id] = score.clamp(-100.0, 100.0);
    }
    return profileFromIssueScores(
      issueScores: issueScores,
      issues: issues,
      dealbreakerIssueIds: dealbreakerIssueIds,
    );
  }

  static SpectrumProfile profileFromPolitician({
    required Politician politician,
    required List<Issue> issues,
  }) {
    return profileFromIssueScores(
      issueScores: politician.issues,
      issues: issues,
    );
  }

  static double vectorDistance(
    Map<String, double> a,
    Map<String, double> b, [
    Map<String, double>? issueWeights,
  ]) {
    final shared = a.keys.where(b.containsKey).toList();
    if (shared.isEmpty) return 999;
    var sum = 0.0;
    var wSum = 0.0;
    for (final id in shared) {
      final w = issueWeights == null || issueWeights.isEmpty
          ? 1.0
          : (issueWeights[id] ?? 1.0);
      if (w <= 0) continue;
      sum += (a[id]! - b[id]!).abs() * w;
      wSum += w;
    }
    if (wSum == 0) return 999;
    return sum / wSum;
  }

  static int closenessFromDistance(double distance) {
    return ((1.0 - (distance / 200.0).clamp(0.0, 1.0)) * 100).round();
  }

  static List<String> dealbreakerHits({
    required Map<String, double> user,
    required Map<String, double> politician,
    required List<String> dealbreakerIssueIds,
  }) {
    final hits = <String>[];
    for (final id in dealbreakerIssueIds) {
      final u = user[id];
      final p = politician[id];
      if (u == null || p == null) continue;
      if ((u - p).abs() >= dealbreakerDiff) hits.add(id);
    }
    return hits;
  }

  static List<IssueOverlap> _overlaps(
    Map<String, double> user,
    Map<String, double> politician,
  ) {
    final shared = user.keys.where(politician.containsKey);
    return [
      for (final id in shared)
        IssueOverlap(
          issueId: id,
          diff: (user[id]! - politician[id]!).abs(),
          userScore: user[id]!,
          politicianScore: politician[id]!,
        ),
    ];
  }

  static String matchStory({
    required List<IssueOverlap> agreements,
    required List<IssueOverlap> disagreements,
    required Map<String, String> issueLabels,
  }) {
    String name(IssueOverlap o) => issueLabels[o.issueId] ?? o.issueId;
    final aligned = agreements.take(2).map(name).toList();
    final diverged = disagreements.take(2).map(name).toList();
    if (aligned.isEmpty && diverged.isEmpty) {
      return 'Issue overlap is mixed across the board.';
    }
    final parts = <String>[];
    if (aligned.isNotEmpty) {
      parts.add('You aligned on ${aligned.join(' and ')}');
    }
    if (diverged.isNotEmpty) {
      parts.add('diverged on ${diverged.join(' and ')}');
    }
    if (parts.length == 1) return '${parts.first}.';
    return '${parts[0]}, but ${parts[1]}.';
  }

  static List<MatchResult> rankPoliticians({
    required SpectrumProfile user,
    required List<Politician> politicians,
    required List<Issue> issues,
  }) {
    final ranked = <MatchResult>[];
    final weights = user.issueWeights.isEmpty ? null : user.issueWeights;
    for (final p in politicians) {
      final pProfile = profileFromPolitician(politician: p, issues: issues);
      final overlaps = _overlaps(user.issueScores, p.issues)
        ..sort((a, b) => a.diff.compareTo(b.diff));
      final agreements = overlaps.take(3).toList();
      final disagreements = overlaps.reversed.take(2).toList();
      final distance = vectorDistance(user.issueScores, p.issues, weights);
      ranked.add(
        MatchResult(
          politician: p,
          distance: distance,
          closeness: closenessFromDistance(distance),
          agreements: agreements,
          disagreements: disagreements,
          axisScore: pProfile.axisScore,
          dealbreakerHits: dealbreakerHits(
            user: user.issueScores,
            politician: p.issues,
            dealbreakerIssueIds: user.dealbreakerIssueIds,
          ),
        ),
      );
    }
    ranked.sort((a, b) {
      if (a.hasDealbreaker != b.hasDealbreaker) {
        return a.hasDealbreaker ? 1 : -1;
      }
      return a.distance.compareTo(b.distance);
    });
    return ranked;
  }

  /// Closest figure whose service ended before [floorYear].
  static Politician? politicalAncestry({
    required Politician person,
    required List<Politician> roster,
    required List<Issue> issues,
    int floorYear = FigureFloor.year2000,
  }) {
    final past = [
      for (final p in roster)
        if (p.id != person.id && !p.servedSince(floorYear)) p,
    ];
    if (past.isEmpty) return null;
    final ranked = rankPoliticians(
      user: profileFromPolitician(politician: person, issues: issues),
      politicians: past,
      issues: issues,
    );
    return ranked.isEmpty ? null : ranked.first.politician;
  }

  static ({
    double distance,
    int closeness,
    List<IssueOverlap> agreements,
    List<IssueOverlap> disagreements,
    String story,
  })
  compareProfiles({
    required SpectrumProfile self,
    required SpectrumProfile other,
    required Map<String, String> issueLabels,
  }) {
    final venn = civicVenn(self: self, other: other);
    final agreements = venn.aligned;
    final disagreements = [...venn.youMoreLiberal, ...venn.theyMoreLiberal]
      ..sort((a, b) => b.diff.compareTo(a.diff));
    final distance = vectorDistance(
      self.issueScores,
      other.issueScores,
      self.issueWeights.isEmpty ? null : self.issueWeights,
    );
    return (
      distance: distance,
      closeness: closenessFromDistance(distance),
      agreements: agreements,
      disagreements: disagreements,
      story: matchStory(
        agreements: agreements,
        disagreements: disagreements,
        issueLabels: issueLabels,
      ),
    );
  }

  /// Every issue either person scored, split for a sit-together Venn.
  static CivicVenn civicVenn({
    required SpectrumProfile self,
    required SpectrumProfile other,
  }) {
    final overlaps = _overlaps(self.issueScores, other.issueScores);
    final aligned = <IssueOverlap>[];
    final youMoreLiberal = <IssueOverlap>[];
    final theyMoreLiberal = <IssueOverlap>[];
    for (final o in overlaps) {
      if (o.diff < vennAlignMaxDiff) {
        aligned.add(o);
      } else if (o.userScore < o.politicianScore) {
        youMoreLiberal.add(o);
      } else {
        theyMoreLiberal.add(o);
      }
    }
    for (final id in self.issueScores.keys) {
      if (other.issueScores.containsKey(id)) continue;
      final you = self.issueScores[id]!;
      if (you.abs() < vennAlignMaxDiff) continue;
      final gap = IssueOverlap(
        issueId: id,
        diff: you.abs(),
        userScore: you,
        politicianScore: 0,
      );
      if (you < 0) {
        youMoreLiberal.add(gap);
      } else {
        theyMoreLiberal.add(gap);
      }
    }
    for (final id in other.issueScores.keys) {
      if (self.issueScores.containsKey(id)) continue;
      final them = other.issueScores[id]!;
      if (them.abs() < vennAlignMaxDiff) continue;
      final gap = IssueOverlap(
        issueId: id,
        diff: them.abs(),
        userScore: 0,
        politicianScore: them,
      );
      if (them < 0) {
        theyMoreLiberal.add(gap);
      } else {
        youMoreLiberal.add(gap);
      }
    }
    aligned.sort((a, b) => a.diff.compareTo(b.diff));
    youMoreLiberal.sort((a, b) => b.diff.compareTo(a.diff));
    theyMoreLiberal.sort((a, b) => b.diff.compareTo(a.diff));
    return CivicVenn(
      aligned: aligned,
      youMoreLiberal: youMoreLiberal,
      theyMoreLiberal: theyMoreLiberal,
    );
  }

  static String importanceLabelForWeight(double weight) {
    var best = defaultImportanceIndex;
    var bestDiff = double.infinity;
    for (var i = 0; i < importanceWeights.length; i++) {
      final d = (importanceWeights[i] - weight).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = i;
      }
    }
    return importanceLabels[best];
  }

  static bool isHeavilySkewed(double score) => score.abs() >= steelManAbsScore;

  /// Steel-man copy for [issueId] when the user landed on the question's side.
  /// The stored argument defends disagreeing, so we only return a question
  /// whose agree-direction matches the user's lean.
  static Question? steelManQuestion({
    required String issueId,
    required double userScore,
    required List<Question> questions,
  }) {
    if (!isHeavilySkewed(userScore)) return null;
    final wantPolarity = userScore < 0 ? -1 : 1;
    for (final q in questions) {
      if (q.issueId == issueId && q.polarity == wantPolarity && q.hasSteelMan) {
        return q;
      }
    }
    return null;
  }

  static String formatScore(double score) {
    final parts = splitScore(score);
    return '${parts.side} ${parts.magnitude}';
  }

  /// The side word and the number apart, for chips too narrow to fit
  /// "Conservative 100" on one line — the number must never be the part
  /// that gets ellipsized away.
  static ({String side, String magnitude}) splitScore(double score) {
    final abs = score.abs().round();
    if (abs == 0) return (side: 'Center', magnitude: '0');
    return (side: score < 0 ? 'Liberal' : 'Conservative', magnitude: '$abs');
  }

  static String labelForScore(double score) {
    final abs = score.abs();
    if (abs < 8) return 'Centrist';
    final side = score < 0 ? 'liberal' : 'conservative';
    if (abs < 25) return 'Slightly $side';
    if (abs < 50) return 'Moderately $side';
    if (abs < 75) return 'Strongly $side';
    return 'Very $side';
  }

  /// How much a roll-call average should pull a curated issue score.
  static double rollcallWeight(int n) => n / (n + rollcallPrior);

  /// Nudge one issue from an Agree/Disagree widget tap. Does not replace the quiz.
  static SpectrumProfile applyMicroCalibration({
    required SpectrumProfile profile,
    required List<Issue> issues,
    required String issueId,
    required int polarity,
    required bool agree,
  }) {
    final tap = contribution(likertIndex: agree ? 4 : 0, polarity: polarity);
    final current = profile.issueScores[issueId];
    final next = current == null
        ? (tap * 0.45).clamp(-100.0, 100.0)
        : ((1 - microCalibrationWeight) * current +
                  microCalibrationWeight * tap)
              .clamp(-100.0, 100.0);
    final scores = Map<String, double>.from(profile.issueScores)
      ..[issueId] = next;
    return profileFromIssueScores(
      issueScores: scores,
      issues: issues,
      issueWeights: profile.issueWeights.isEmpty ? null : profile.issueWeights,
      dealbreakerIssueIds: profile.dealbreakerIssueIds,
    );
  }

  static double blendRollcall({
    required double curated,
    required double rollcall,
    required int n,
  }) {
    if (n < rollcallMinVotes) return curated;
    final w = rollcallWeight(n);
    return ((1 - w) * curated + w * rollcall).clamp(-100.0, 100.0);
  }

  static Politician applyRollcall(
    Politician person,
    Map<String, dynamic>? member,
  ) {
    if (member == null) return person;
    final sessions = RollcallSession.listFrom(member['sessions']);
    final rawIssues = member['issues'];
    final rawCounts = member['counts'];
    if (rawIssues is! Map || rawCounts is! Map) {
      return sessions.isEmpty
          ? person
          : person.copyWith(rollcallSessions: sessions);
    }
    final issues = Map<String, double>.from(person.issues);
    final confidence = Map<String, String>.from(person.confidence);
    final counts = <String, int>{};
    for (final entry in rawIssues.entries) {
      final id = '${entry.key}';
      final n = (rawCounts[id] as num?)?.toInt() ?? 0;
      if (n < rollcallMinVotes) continue;
      final rollcall = (entry.value as num).toDouble();
      final curated = issues[id];
      issues[id] = curated == null
          ? rollcall.clamp(-100, 100)
          : blendRollcall(curated: curated, rollcall: rollcall, n: n);
      confidence[id] = 'rollcall';
      counts[id] = n;
    }
    if (counts.isEmpty && sessions.isEmpty) return person;
    return person.copyWith(
      issues: counts.isEmpty ? person.issues : issues,
      confidence: counts.isEmpty ? person.confidence : confidence,
      rollcallCounts: counts.isEmpty ? person.rollcallCounts : counts,
      rollcallSessions: sessions,
    );
  }
}
