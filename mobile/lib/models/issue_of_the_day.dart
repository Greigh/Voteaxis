import 'question.dart';
import '../services/voteaxis_api.dart';

class IssueOfTheDay {
  const IssueOfTheDay({
    required this.issueId,
    required this.headline,
    required this.question,
    required this.polarity,
    required this.dayKey,
    this.source = 'bank',
  });

  final String issueId;
  final String headline;
  final String question;
  final int polarity;
  final String dayKey;
  final String source;

  static String dateKey(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Prefer the editorial week prompt; otherwise rotate a modern quiz item by day.
  static IssueOfTheDay resolve({
    IssueOfTheWeek? week,
    required List<Question> questions,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final key = dateKey(today);
    final modern = [
      for (final q in questions)
        if (!q.isHistorical) q,
    ];
    if (week != null && week.issueId.isNotEmpty && week.question.isNotEmpty) {
      Question? match;
      for (final q in modern) {
        if (q.issueId == week.issueId) {
          match = q;
          break;
        }
      }
      return IssueOfTheDay(
        issueId: week.issueId,
        headline: week.headline.isEmpty ? 'Issue of the day' : week.headline,
        question: week.question,
        polarity: match?.polarity ?? -1,
        dayKey: key,
        source: 'week',
      );
    }
    if (modern.isEmpty) {
      return IssueOfTheDay(
        issueId: 'taxes',
        headline: 'Issue of the day',
        question: 'Open Voteaxis to take the quiz.',
        polarity: -1,
        dayKey: key,
      );
    }
    final index = today.difference(DateTime(today.year)).inDays % modern.length;
    final q = modern[index];
    return IssueOfTheDay(
      issueId: q.issueId,
      headline: 'Issue of the day',
      question: q.text,
      polarity: q.polarity,
      dayKey: key,
    );
  }
}
