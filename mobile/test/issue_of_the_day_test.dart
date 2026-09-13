import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/models/issue_of_the_day.dart';
import 'package:voteaxis/models/question.dart';
import 'package:voteaxis/services/voteaxis_api.dart';

void main() {
  const modern = [
    Question(id: 'a', issueId: 'taxes', text: 'Raise top rates?', polarity: -1),
    Question(
      id: 'b',
      issueId: 'border',
      text: 'Tighten the border?',
      polarity: 1,
    ),
  ];
  const historical = Question(
    id: 'h',
    issueId: 'trusts',
    text: 'Break the trusts?',
    polarity: -1,
    era: 'historical',
  );

  test('dateKey is calendar YYYY-MM-DD', () {
    expect(IssueOfTheDay.dateKey(DateTime(2026, 8, 13)), '2026-08-13');
  });

  test('prefers the editorial week prompt and matching polarity', () {
    const week = IssueOfTheWeek(
      weekOf: '2026-08-10',
      issueId: 'border',
      headline: 'Who belongs?',
      question: 'Expand paths or tighten enforcement?',
    );
    final issue = IssueOfTheDay.resolve(
      week: week,
      questions: modern,
      now: DateTime(2026, 8, 13),
    );
    expect(issue.issueId, 'border');
    expect(issue.headline, 'Who belongs?');
    expect(issue.question, 'Expand paths or tighten enforcement?');
    expect(issue.polarity, 1);
    expect(issue.source, 'week');
    expect(issue.dayKey, '2026-08-13');
  });

  test(
    'week without a matching quiz item defaults polarity to liberal-agree',
    () {
      const week = IssueOfTheWeek(
        weekOf: '2026-08-10',
        issueId: 'unknown',
        headline: 'New issue',
        question: 'What now?',
      );
      final issue = IssueOfTheDay.resolve(week: week, questions: modern);
      expect(issue.polarity, -1);
      expect(issue.source, 'week');
    },
  );

  test('rotates modern quiz items by day of year and skips historical', () {
    final pool = [...modern, historical];
    final jan1 = IssueOfTheDay.resolve(
      questions: pool,
      now: DateTime(2026, 1, 1),
    );
    final jan2 = IssueOfTheDay.resolve(
      questions: pool,
      now: DateTime(2026, 1, 2),
    );
    expect(jan1.issueId, 'taxes');
    expect(jan1.question, 'Raise top rates?');
    expect(jan1.source, 'bank');
    expect(jan2.issueId, 'border');
    expect(jan1.issueId, isNot(historical.issueId));
  });

  test('empty modern bank falls back to an open-the-app prompt', () {
    final issue = IssueOfTheDay.resolve(
      questions: const [historical],
      now: DateTime(2026, 3, 1),
    );
    expect(issue.issueId, 'taxes');
    expect(issue.question, contains('Open Voteaxis'));
  });
}
