import 'politician.dart';
import 'quiz_bank.dart';

/// Every user-tunable preference in one value, so the shell, the settings
/// screen, and a transferred backup all agree on the same defaults.
class AppSettings {
  const AppSettings({
    this.figureFloor = FigureFloor.year2000,
    this.timeBlind = false,
    this.skipQuiz = false,
    this.quizLength = QuizBank.defaultLength,
    this.dealbreakerPrompts = true,
    this.haptics = true,
    this.reduceMotion = false,
    this.issueWidget = true,
  });

  /// Earliest era of figures to match against.
  final int figureFloor;

  /// Hide years and ordinals on the match list.
  final bool timeBlind;

  /// Lead the hub with hand-set placement instead of the quiz.
  final bool skipQuiz;

  /// Questions drawn per run.
  final int quizLength;

  /// Show the "mark as a dealbreaker" control during the quiz.
  final bool dealbreakerPrompts;

  final bool haptics;
  final bool reduceMotion;

  /// Keep the Issue of the Day home-screen widget fed.
  final bool issueWidget;

  /// Time-blind only exists below the 2000s floor, so a stored `true` from an
  /// older floor must not leak back in when the floor moves up.
  AppSettings get normalized {
    final floor = FigureFloor.coerce(figureFloor);
    return copyWith(
      figureFloor: floor,
      timeBlind: FigureFloor.showsPastUi(floor) && timeBlind,
      quizLength: QuizBank.coerceLength(quizLength),
    );
  }

  bool get showsPastUi => FigureFloor.showsPastUi(figureFloor);

  AppSettings copyWith({
    int? figureFloor,
    bool? timeBlind,
    bool? skipQuiz,
    int? quizLength,
    bool? dealbreakerPrompts,
    bool? haptics,
    bool? reduceMotion,
    bool? issueWidget,
  }) {
    return AppSettings(
      figureFloor: figureFloor ?? this.figureFloor,
      timeBlind: timeBlind ?? this.timeBlind,
      skipQuiz: skipQuiz ?? this.skipQuiz,
      quizLength: quizLength ?? this.quizLength,
      dealbreakerPrompts: dealbreakerPrompts ?? this.dealbreakerPrompts,
      haptics: haptics ?? this.haptics,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      issueWidget: issueWidget ?? this.issueWidget,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.figureFloor == figureFloor &&
      other.timeBlind == timeBlind &&
      other.skipQuiz == skipQuiz &&
      other.quizLength == quizLength &&
      other.dealbreakerPrompts == dealbreakerPrompts &&
      other.haptics == haptics &&
      other.reduceMotion == reduceMotion &&
      other.issueWidget == issueWidget;

  @override
  int get hashCode => Object.hash(
    figureFloor,
    timeBlind,
    skipQuiz,
    quizLength,
    dealbreakerPrompts,
    haptics,
    reduceMotion,
    issueWidget,
  );
}
