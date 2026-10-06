import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/politician.dart';
import '../models/quiz_bank.dart';
import '../models/scoring.dart';
import 'share_link.dart';

class QuizRun {
  QuizRun({
    required this.timestampMs,
    required this.issueScores,
    required this.pillarScores,
    required this.axisScore,
    this.issueWeights = const {},
    this.dealbreakerIssueIds = const [],
    this.label,
  });

  /// Stamped on a placement the user set by hand instead of taking the quiz.
  static const handSetLabel = 'Set by hand';

  final int timestampMs;
  final Map<String, double> issueScores;
  final Map<String, double> pillarScores;
  final double axisScore;
  final Map<String, double> issueWeights;
  final List<String> dealbreakerIssueIds;
  final String? label;

  bool get isHandSet => label == handSetLabel;

  SpectrumProfile toProfile() => SpectrumProfile(
    issueScores: issueScores,
    pillarScores: pillarScores,
    axisScore: axisScore,
    issueWeights: issueWeights,
    dealbreakerIssueIds: dealbreakerIssueIds,
  );

  Map<String, dynamic> toJson() => {
    'timestampMs': timestampMs,
    'issueScores': issueScores,
    'pillarScores': pillarScores,
    'axisScore': axisScore,
    'issueWeights': issueWeights,
    'dealbreakerIssueIds': dealbreakerIssueIds,
    if (label != null) 'label': label,
  };

  factory QuizRun.fromJson(Map<String, dynamic> json) {
    return QuizRun(
      timestampMs: json['timestampMs'] as int,
      issueScores: (json['issueScores'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      ),
      pillarScores: (json['pillarScores'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      ),
      axisScore: (json['axisScore'] as num).toDouble(),
      issueWeights:
          (json['issueWeights'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ) ??
          const {},
      dealbreakerIssueIds:
          (json['dealbreakerIssueIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      label: json['label'] as String?,
    );
  }

  factory QuizRun.fromProfile(SpectrumProfile profile, {String? label}) {
    return QuizRun(
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      issueScores: Map<String, double>.from(profile.issueScores),
      pillarScores: Map<String, double>.from(profile.pillarScores),
      axisScore: profile.axisScore,
      issueWeights: Map<String, double>.from(profile.issueWeights),
      dealbreakerIssueIds: List<String>.from(profile.dealbreakerIssueIds),
      label: label,
    );
  }
}

class QuizProgress {
  const QuizProgress({
    required this.answers,
    required this.index,
    required this.questionIds,
    required this.importanceIndexes,
    required this.dealbreakerIssueIds,
  });

  final List<int?> answers;
  final int index;
  final List<String> questionIds;
  final List<int> importanceIndexes;
  final List<String> dealbreakerIssueIds;
}

class ResultStore {
  ResultStore({FlutterSecureStorage? secureStorage})
    : _secure =
          secureStorage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _secure;

  static const _runsKey = 'quiz_runs_v2';
  static const _progressKey = 'quiz_progress_v1';
  static const _onboardedKey = 'has_onboarded_v1';
  static const _homeStateKey = 'home_state_v1';
  static const _homeDistrictKey = 'home_district_v1';
  static const _figureFloorKey = 'figure_floor_v1';
  static const _includePastKey = 'include_past_v1';
  static const _timeBlindKey = 'time_blind_v1';
  static const _skipQuizKey = 'skip_quiz_v1';
  static const _quizLengthKey = 'quiz_length_v1';
  static const _dealbreakerPromptsKey = 'dealbreaker_prompts_v1';
  static const _hapticsKey = 'haptics_v1';
  static const _reduceMotionKey = 'reduce_motion_v1';
  static const _issueWidgetKey = 'issue_widget_v1';
  static const _themeKey = 'theme_v1';
  static const _dailyReminderKey = 'daily_reminder_v1';
  static const _calibratedDayKey = 'micro_calibrated_day_v1';
  static const _maxRuns = 10;

  /// Everything a full reset has to clear. Secure-storage keys are wiped
  /// separately because they never live in prefs.
  static const _prefKeys = [
    _onboardedKey,
    _homeStateKey,
    _homeDistrictKey,
    _figureFloorKey,
    _includePastKey,
    _timeBlindKey,
    _skipQuizKey,
    _quizLengthKey,
    _dealbreakerPromptsKey,
    _hapticsKey,
    _reduceMotionKey,
    _issueWidgetKey,
    _themeKey,
    _dailyReminderKey,
    _calibratedDayKey,
  ];

  static const _shareLinkKey = 'share_link_v1';

  static const _secureKeys = [_runsKey, _progressKey, _shareLinkKey];

  Future<String?> _readAnswers(String key) async {
    final secure = await _secure.read(key: key);
    if (secure != null && secure.isNotEmpty) return secure;
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(key);
    if (legacy == null || legacy.isEmpty) return null;
    await _secure.write(key: key, value: legacy);
    await prefs.remove(key);
    return legacy;
  }

  Future<void> _writeAnswers(String key, String value) async {
    await _secure.write(key: key, value: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<void> _deleteAnswers(String key) async {
    await _secure.delete(key: key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<bool> hasOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardedKey) ?? false;
  }

  Future<void> setOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardedKey, true);
  }

  Future<String?> loadHomeState() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_homeStateKey);
    if (code == null || code.isEmpty) return null;
    return code;
  }

  Future<void> saveHomeState(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_homeStateKey, code);
  }

  /// The user's U.S. House district (1-based) inside [loadHomeState]'s state.
  /// Null means the ballot only knows the state — House matches stay
  /// state-wide rather than guessing a district.
  Future<int?> loadHomeDistrict() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_homeDistrictKey);
    if (stored == null || stored < 1) return null;
    return stored;
  }

  /// Pass null to clear — e.g. when the home state changes and the stored
  /// district belongs to the old map.
  Future<void> saveHomeDistrict(int? district) async {
    final prefs = await SharedPreferences.getInstance();
    if (district == null || district < 1) {
      await prefs.remove(_homeDistrictKey);
    } else {
      await prefs.setInt(_homeDistrictKey, district);
    }
  }

  Future<int> loadFigureFloor() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_figureFloorKey);
    if (stored != null) return FigureFloor.coerce(stored);
    if (prefs.getBool(_includePastKey) ?? false) return FigureFloor.year1960;
    return FigureFloor.year2000;
  }

  Future<void> saveFigureFloor(int year) async {
    final prefs = await SharedPreferences.getInstance();
    final floor = FigureFloor.coerce(year);
    await prefs.setInt(_figureFloorKey, floor);
    if (!FigureFloor.showsPastUi(floor)) await saveTimeBlind(false);
  }

  Future<bool> loadTimeBlind() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_timeBlindKey) ?? false;
  }

  Future<void> saveTimeBlind(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_timeBlindKey, value);
  }

  /// The write token for a published result page. Secure storage because
  /// holding it is what lets this device replace or revoke that page.
  Future<StoredShareLink?> loadShareLink() async {
    final raw = await _secure.read(key: _shareLinkKey);
    if (raw == null || raw.isEmpty) return null;
    final link = StoredShareLink.fromRaw(raw);
    if (link == null || link.isExpired) {
      await _secure.delete(key: _shareLinkKey);
      return null;
    }
    return link;
  }

  Future<void> saveShareLink(StoredShareLink link) async {
    await _secure.write(key: _shareLinkKey, value: jsonEncode(link.toJson()));
  }

  Future<void> clearShareLink() async {
    await _secure.delete(key: _shareLinkKey);
  }

  Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      figureFloor: await loadFigureFloor(),
      timeBlind: prefs.getBool(_timeBlindKey) ?? false,
      skipQuiz: prefs.getBool(_skipQuizKey) ?? false,
      quizLength: QuizBank.coerceLength(prefs.getInt(_quizLengthKey)),
      dealbreakerPrompts: prefs.getBool(_dealbreakerPromptsKey) ?? true,
      haptics: prefs.getBool(_hapticsKey) ?? true,
      reduceMotion: prefs.getBool(_reduceMotionKey) ?? false,
      issueWidget: prefs.getBool(_issueWidgetKey) ?? true,
      theme:
          AppThemeMode.values.asNameMap()[prefs.getString(_themeKey)] ??
          AppThemeMode.system,
      dailyReminder: prefs.getBool(_dailyReminderKey) ?? false,
    ).normalized;
  }

  Future<void> saveSettings(AppSettings settings) async {
    final next = settings.normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_figureFloorKey, next.figureFloor);
    await prefs.setBool(_timeBlindKey, next.timeBlind);
    await prefs.setBool(_skipQuizKey, next.skipQuiz);
    await prefs.setInt(_quizLengthKey, next.quizLength);
    await prefs.setBool(_dealbreakerPromptsKey, next.dealbreakerPrompts);
    await prefs.setBool(_hapticsKey, next.haptics);
    await prefs.setBool(_reduceMotionKey, next.reduceMotion);
    await prefs.setBool(_issueWidgetKey, next.issueWidget);
    await prefs.setString(_themeKey, next.theme.name);
    await prefs.setBool(_dailyReminderKey, next.dailyReminder);
  }

  /// Wipes results, drafts, and preferences. The next launch starts at
  /// onboarding as if the app had just been installed.
  Future<void> clearEverything() async {
    for (final key in _secureKeys) {
      await _deleteAnswers(key);
    }
    final prefs = await SharedPreferences.getInstance();
    for (final key in _prefKeys) {
      await prefs.remove(key);
    }
  }

  /// Drops saved runs but keeps preferences and the home state.
  Future<void> clearResults() async {
    await _deleteAnswers(_runsKey);
    await _deleteAnswers(_progressKey);
  }

  Future<String?> loadCalibrationDay() async {
    final prefs = await SharedPreferences.getInstance();
    final day = prefs.getString(_calibratedDayKey);
    if (day == null || day.isEmpty) return null;
    return day;
  }

  Future<void> saveCalibrationDay(String day) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_calibratedDayKey, day);
  }

  Future<void> replaceLatestRun(QuizRun run) async {
    final runs = await loadRuns();
    if (runs.isEmpty) {
      await _writeAnswers(_runsKey, jsonEncode([run.toJson()]));
      return;
    }
    runs[0] = run;
    await _writeAnswers(
      _runsKey,
      jsonEncode(runs.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> saveRun(QuizRun run) async {
    final runs = await loadRuns();
    runs.insert(0, run);
    while (runs.length > _maxRuns) {
      runs.removeLast();
    }
    await _writeAnswers(
      _runsKey,
      jsonEncode(runs.map((r) => r.toJson()).toList()),
    );
    await clearProgress();
  }

  Future<List<QuizRun>> loadRuns() async {
    final raw = await _readAnswers(_runsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => QuizRun.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<QuizRun?> latestRun() async {
    final runs = await loadRuns();
    return runs.isEmpty ? null : runs.first;
  }

  Future<void> saveProgress(
    List<int?> answers,
    int index, {
    required List<String> questionIds,
    List<int>? importanceIndexes,
    List<String>? dealbreakerIssueIds,
  }) async {
    final answered = answers.where((e) => e != null).length;
    if (answered == 0 && index == 0) {
      await _deleteAnswers(_progressKey);
      return;
    }
    await _writeAnswers(
      _progressKey,
      jsonEncode({
        'index': index,
        'answers': answers,
        'questionIds': questionIds,
        'importanceIndexes':
            importanceIndexes ??
            List<int>.filled(answers.length, Scoring.defaultImportanceIndex),
        'dealbreakerIssueIds': dealbreakerIssueIds ?? const <String>[],
      }),
    );
  }

  Future<QuizProgress?> loadProgress() async {
    final raw = await _readAnswers(_progressKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final answers = (map['answers'] as List<dynamic>)
          .map((e) => e == null ? null : (e as num).toInt())
          .toList();
      final index = (map['index'] as num).toInt();
      final questionIds =
          (map['questionIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[];
      if (answers.every((e) => e == null)) return null;
      if (questionIds.isNotEmpty && questionIds.length != answers.length) {
        await _deleteAnswers(_progressKey);
        return null;
      }
      var importance =
          (map['importanceIndexes'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          List<int>.filled(answers.length, Scoring.defaultImportanceIndex);
      if (importance.length != answers.length) {
        importance = List<int>.filled(
          answers.length,
          Scoring.defaultImportanceIndex,
        );
      }
      final dealbreakers =
          (map['dealbreakerIssueIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[];
      return QuizProgress(
        answers: answers,
        index: index.clamp(0, answers.length - 1),
        questionIds: questionIds,
        importanceIndexes: importance,
        dealbreakerIssueIds: dealbreakers,
      );
    } catch (_) {
      await _deleteAnswers(_progressKey);
      return null;
    }
  }

  Future<void> clearProgress() async {
    await _deleteAnswers(_progressKey);
  }
}
