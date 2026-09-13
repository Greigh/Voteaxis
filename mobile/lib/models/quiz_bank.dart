import 'dart:math';

import 'question.dart';

/// Builds a fresh 25-question quiz from a larger bank.
///
/// Guarantees at least one question per issue when possible, then fills
/// remaining slots with alternate wordings so runs feel different.
class QuizBank {
  QuizBank._();

  static const defaultLength = 25;

  /// Quiz lengths offered in settings. 81 questions in the bank, so even the
  /// long run still draws distinct wordings.
  static const lengthOptions = [12, 25, 40];

  static const lengthLabels = {12: 'Short', 25: 'Standard', 40: 'Long'};

  static const lengthBlurbs = {
    12: '12 questions — one per issue, about a minute.',
    25: '25 questions — the balanced default, about three minutes.',
    40: '40 questions — extra wordings per issue for a steadier read.',
  };

  static int coerceLength(int? length) =>
      lengthOptions.contains(length) ? length! : defaultLength;

  static List<Question> draw({
    required List<Question> pool,
    int length = defaultLength,
    Random? random,
    bool includeHistorical = false,
  }) {
    final eligible = [
      for (final q in pool)
        if (includeHistorical || !q.isHistorical) q,
    ];
    if (eligible.isEmpty) return const [];
    final rng = random ?? Random();

    final byIssue = <String, List<Question>>{};
    for (final q in eligible) {
      byIssue.putIfAbsent(q.issueId, () => []).add(q);
    }
    for (final variants in byIssue.values) {
      variants.shuffle(rng);
    }

    final selected = <Question>[];
    final issueIds = byIssue.keys.toList()..shuffle(rng);

    // Cover every issue first.
    for (final issueId in issueIds) {
      final variants = byIssue[issueId]!;
      if (variants.isEmpty) continue;
      selected.add(variants.removeAt(0));
      if (selected.length >= length) break;
    }

    // Fill with leftover alternates.
    final leftovers = byIssue.values.expand((e) => e).toList()..shuffle(rng);
    while (selected.length < length && leftovers.isNotEmpty) {
      selected.add(leftovers.removeAt(0));
    }

    selected.shuffle(rng);
    return selected;
  }
}
