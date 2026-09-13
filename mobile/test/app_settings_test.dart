import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/models/app_settings.dart';
import 'package:voteaxis/models/politician.dart';
import 'package:voteaxis/models/quiz_bank.dart';

void main() {
  test('defaults match the shipped experience', () {
    const settings = AppSettings();
    expect(settings.figureFloor, FigureFloor.year2000);
    expect(settings.timeBlind, isFalse);
    expect(settings.skipQuiz, isFalse);
    expect(settings.quizLength, QuizBank.defaultLength);
    expect(settings.dealbreakerPrompts, isTrue);
    expect(settings.haptics, isTrue);
    expect(settings.reduceMotion, isFalse);
    expect(settings.issueWidget, isTrue);
  });

  test('normalize drops time-blind above the 2000s floor', () {
    const settings = AppSettings(
      figureFloor: FigureFloor.year2000,
      timeBlind: true,
    );
    expect(settings.normalized.timeBlind, isFalse);
  });

  test('normalize keeps time-blind on the eras that show it', () {
    const settings = AppSettings(
      figureFloor: FigureFloor.year1960,
      timeBlind: true,
    );
    expect(settings.normalized.timeBlind, isTrue);
    expect(settings.normalized.showsPastUi, isTrue);
  });

  test('normalize coerces a floor and a length it does not offer', () {
    const settings = AppSettings(figureFloor: 1942, quizLength: 99);
    expect(settings.normalized.figureFloor, FigureFloor.year2000);
    expect(settings.normalized.quizLength, QuizBank.defaultLength);
  });

  test('copyWith changes one field and leaves the rest alone', () {
    const settings = AppSettings(skipQuiz: true, haptics: false);
    final next = settings.copyWith(quizLength: 12);
    expect(next.quizLength, 12);
    expect(next.skipQuiz, isTrue);
    expect(next.haptics, isFalse);
  });

  test('equality is by value, so a no-op save is detectable', () {
    expect(const AppSettings(), const AppSettings());
    expect(const AppSettings().hashCode, const AppSettings().hashCode);
    expect(const AppSettings(), isNot(const AppSettings(skipQuiz: true)));
  });
}
