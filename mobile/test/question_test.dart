import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/models/question.dart';

void main() {
  test('fromJson defaults era to modern', () {
    final q = Question.fromJson({
      'id': 'taxes_a',
      'issueId': 'taxes',
      'text': 'Raise taxes on the rich.',
      'polarity': -1,
    });
    expect(q.era, 'modern');
    expect(q.isHistorical, isFalse);
  });

  test('historical era flags 1912-style questions', () {
    final q = Question.fromJson({
      'id': 'taxes_1912',
      'issueId': 'taxes',
      'text': 'I would back a federal income tax on the very rich.',
      'polarity': -1,
      'era': 'historical',
    });
    expect(q.isHistorical, isTrue);
  });

  test('fromJson reads an optional steel_man_argument', () {
    final q = Question.fromJson({
      'id': 'taxes_a',
      'issueId': 'taxes',
      'text': 'Raise taxes on the rich.',
      'polarity': -1,
      'steel_man_argument': 'Capital is mobile; incidence may fall on labor.',
    });
    expect(q.hasSteelMan, isTrue);
    expect(q.steelManArgument, contains('incidence'));
  });
}
