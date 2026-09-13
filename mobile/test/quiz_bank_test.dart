import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/models/question.dart';
import 'package:voteaxis/models/quiz_bank.dart';

void main() {
  final pool = [
    for (final issue in const [
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
    ])
      for (var i = 0; i < 3; i++)
        Question(
          id: '${issue}_$i',
          issueId: issue,
          text: '$issue variant $i',
          polarity: i.isEven ? 1 : -1,
        ),
  ];

  test('draw returns requested length with issue coverage', () {
    final quiz = QuizBank.draw(pool: pool, length: 25, random: Random(7));
    expect(quiz, hasLength(25));
    final issues = quiz.map((q) => q.issueId).toSet();
    expect(issues, hasLength(22));
  });

  test('different seeds produce different question sets', () {
    final a = QuizBank.draw(
      pool: pool,
      length: 25,
      random: Random(1),
    ).map((q) => q.id).toList();
    final b = QuizBank.draw(
      pool: pool,
      length: 25,
      random: Random(2),
    ).map((q) => q.id).toList();
    expect(a, isNot(equals(b)));
  });

  test('historical questions stay out of the bank unless 1960s plus', () {
    final mixed = [
      const Question(
        id: 'taxes_now',
        issueId: 'taxes',
        text: 'now',
        polarity: 1,
      ),
      const Question(
        id: 'taxes_1912',
        issueId: 'taxes',
        text: 'then',
        polarity: 1,
        era: 'historical',
      ),
    ];
    final modern = QuizBank.draw(
      pool: mixed,
      length: 2,
      includeHistorical: false,
      random: Random(1),
    );
    expect(modern.map((q) => q.id), ['taxes_now']);
    final deep = QuizBank.draw(
      pool: mixed,
      length: 2,
      includeHistorical: true,
      random: Random(1),
    );
    expect(deep.map((q) => q.id).toSet(), {'taxes_now', 'taxes_1912'});
  });

  group('length options', () {
    test('coerce falls back to the default for anything unoffered', () {
      expect(QuizBank.coerceLength(null), QuizBank.defaultLength);
      expect(QuizBank.coerceLength(7), QuizBank.defaultLength);
      expect(QuizBank.coerceLength(-1), QuizBank.defaultLength);
      for (final length in QuizBank.lengthOptions) {
        expect(QuizBank.coerceLength(length), length);
      }
    });

    test('every offered length has a label and a blurb', () {
      for (final length in QuizBank.lengthOptions) {
        expect(QuizBank.lengthLabels[length], isNotNull);
        expect(QuizBank.lengthBlurbs[length], isNotNull);
      }
    });

    test('a short draw still covers every issue it can', () {
      final pool = [
        for (var i = 0; i < 30; i++)
          Question(
            id: 'q$i',
            issueId: 'issue${i % 12}',
            text: 'Question $i',
            polarity: -1,
          ),
      ];
      final drawn = QuizBank.draw(pool: pool, length: 12, random: Random(7));
      expect(drawn, hasLength(12));
      expect(drawn.map((q) => q.issueId).toSet(), hasLength(12));
    });

    test('a long draw fills past one-per-issue with alternate wordings', () {
      final pool = [
        for (var i = 0; i < 80; i++)
          Question(
            id: 'q$i',
            issueId: 'issue${i % 20}',
            text: 'Question $i',
            polarity: -1,
          ),
      ];
      final drawn = QuizBank.draw(pool: pool, length: 40, random: Random(7));
      expect(drawn, hasLength(40));
      expect(drawn.map((q) => q.id).toSet(), hasLength(40));
    });
  });
}
