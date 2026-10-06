import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voteaxis/models/app_settings.dart';
import 'package:voteaxis/models/politician.dart';
import 'package:voteaxis/services/result_store.dart';
import 'package:voteaxis/services/share_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('save and load in-progress quiz answers with question order', () async {
    final store = ResultStore();
    final answers = List<int?>.filled(5, null);
    answers[0] = 4;
    answers[1] = 2;
    const ids = ['a', 'b', 'c', 'd', 'e'];

    await store.saveProgress(answers, 1, questionIds: ids);
    final loaded = await store.loadProgress();

    expect(loaded, isNotNull);
    expect(loaded!.index, 1);
    expect(loaded.answers, answers);
    expect(loaded.questionIds, ids);
    expect(loaded.importanceIndexes, List<int>.filled(5, 2));
    expect(loaded.dealbreakerIssueIds, isEmpty);
  });

  test('save and load importance and dealbreakers', () async {
    final store = ResultStore();
    await store.saveProgress(
      [4, 2, null],
      1,
      questionIds: const ['a', 'b', 'c'],
      importanceIndexes: const [0, 4, 2],
      dealbreakerIssueIds: const ['taxes'],
    );
    final loaded = await store.loadProgress();
    expect(loaded!.importanceIndexes, [0, 4, 2]);
    expect(loaded.dealbreakerIssueIds, ['taxes']);
  });

  test('empty draft is not treated as in-progress', () async {
    final store = ResultStore();
    await store.saveProgress(
      List<int?>.filled(5, null),
      0,
      questionIds: const ['a', 'b', 'c', 'd', 'e'],
    );
    expect(await store.loadProgress(), isNull);
  });

  test('clearProgress removes draft', () async {
    final store = ResultStore();
    await store.saveProgress(
      [1, null, null],
      0,
      questionIds: const ['a', 'b', 'c'],
    );
    await store.clearProgress();
    expect(await store.loadProgress(), isNull);
  });

  test('saveRun clears in-progress draft', () async {
    final store = ResultStore();
    await store.saveProgress([3, 2, 1], 2, questionIds: const ['a', 'b', 'c']);
    await store.saveRun(
      QuizRun(
        timestampMs: 1,
        issueScores: const {'a': 10},
        pillarScores: const {'p': 10},
        axisScore: 10,
      ),
    );
    expect(await store.loadProgress(), isNull);
  });

  test(
    'figure floor defaults to 2000s plus and migrates include the past',
    () async {
      final store = ResultStore();
      expect(await store.loadFigureFloor(), 2000);
      await store.saveFigureFloor(1980);
      expect(await store.loadFigureFloor(), 1980);

      SharedPreferences.setMockInitialValues({'include_past_v1': true});
      expect(await ResultStore().loadFigureFloor(), 1960);
    },
  );

  test('2000s plus clears time-blind', () async {
    final store = ResultStore();
    await store.saveTimeBlind(true);
    await store.saveFigureFloor(2000);
    expect(await store.loadTimeBlind(), isFalse);
  });

  test('migrates plaintext answers into secure storage', () async {
    SharedPreferences.setMockInitialValues({
      'quiz_progress_v1': jsonEncode({
        'index': 1,
        'answers': [4, 2, null],
        'questionIds': ['a', 'b', 'c'],
      }),
      'quiz_runs_v2': jsonEncode([
        {
          'timestampMs': 1,
          'issueScores': {'taxes': -10},
          'pillarScores': {'economy': -10},
          'axisScore': -10,
        },
      ]),
    });
    final store = ResultStore();
    final progress = await store.loadProgress();
    expect(progress!.answers, [4, 2, null]);
    final runs = await store.loadRuns();
    expect(runs.single.axisScore, -10);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('quiz_progress_v1'), isNull);
    expect(prefs.getString('quiz_runs_v2'), isNull);
    expect((await store.loadProgress())!.answers.first, 4);
    expect((await store.loadRuns()).single.axisScore, -10);
  });

  test('saveRun round-trips a labeled profile', () async {
    final store = ResultStore();
    await store.saveRun(
      QuizRun(
        timestampMs: 42,
        issueScores: const {'taxes': -10},
        pillarScores: const {'economy': -10},
        axisScore: -10,
        issueWeights: const {'taxes': 2.5},
        dealbreakerIssueIds: const ['taxes'],
        label: 'first',
      ),
    );
    final latest = await store.latestRun();
    expect(latest?.label, 'first');
    expect(latest?.toProfile().issueWeights['taxes'], 2.5);
    expect(latest?.dealbreakerIssueIds, ['taxes']);
    expect(await store.loadHomeState(), isNull);
    await store.saveHomeState('MI');
    expect(await store.loadHomeState(), 'MI');
  });

  test(
    'replaceLatestRun updates the newest run without clearing a draft',
    () async {
      final store = ResultStore();
      await store.saveProgress(
        [3, 2, 1],
        2,
        questionIds: const ['a', 'b', 'c'],
      );
      await store.saveRun(
        QuizRun(
          timestampMs: 1,
          issueScores: const {'taxes': 0},
          pillarScores: const {'economy': 0},
          axisScore: 0,
          label: 'first',
        ),
      );
      await store.saveProgress([4], 0, questionIds: const ['d']);
      await store.replaceLatestRun(
        QuizRun(
          timestampMs: 2,
          issueScores: const {'taxes': -20},
          pillarScores: const {'economy': -20},
          axisScore: -20,
          label: 'first',
        ),
      );
      final latest = await store.latestRun();
      expect(latest?.axisScore, -20);
      expect(await store.loadProgress(), isNotNull);
    },
  );

  test('calibration day is stored in prefs', () async {
    final store = ResultStore();
    expect(await store.loadCalibrationDay(), isNull);
    await store.saveCalibrationDay('2026-08-13');
    expect(await store.loadCalibrationDay(), '2026-08-13');
  });

  group('settings bundle', () {
    test('defaults come back when nothing has been saved', () async {
      final settings = await ResultStore().loadSettings();
      expect(settings, const AppSettings());
    });

    test('every field round-trips', () async {
      final store = ResultStore();
      const saved = AppSettings(
        figureFloor: FigureFloor.year1960,
        timeBlind: true,
        skipQuiz: true,
        quizLength: 40,
        dealbreakerPrompts: false,
        haptics: false,
        reduceMotion: true,
        issueWidget: false,
        theme: AppThemeMode.dark,
        dailyReminder: true,
      );
      await store.saveSettings(saved);
      expect(await store.loadSettings(), saved);
    });

    test('saving normalizes rather than storing an impossible pair', () async {
      final store = ResultStore();
      await store.saveSettings(
        const AppSettings(figureFloor: FigureFloor.year2000, timeBlind: true),
      );
      expect((await store.loadSettings()).timeBlind, isFalse);
      expect(await store.loadTimeBlind(), isFalse);
    });

    test('reads a figure floor written by the older single-key path', () async {
      final store = ResultStore();
      await store.saveFigureFloor(1980);
      await store.saveTimeBlind(true);
      final settings = await store.loadSettings();
      expect(settings.figureFloor, 1980);
      expect(settings.timeBlind, isTrue);
    });
  });

  group('share link', () {
    test('round-trips and clears', () async {
      final store = ResultStore();
      expect(await store.loadShareLink(), isNull);
      final link = StoredShareLink(
        id: 'a2b3c4d5e6f7g8h9',
        token: 'f' * 48,
        url: 'https://voteaxis.org/result/a2b3c4d5e6f7g8h9',
        encrypted: true,
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      await store.saveShareLink(link);
      final loaded = await store.loadShareLink();
      expect(loaded?.id, link.id);
      expect(loaded?.token, link.token);
      expect(loaded?.encrypted, isTrue);

      await store.clearShareLink();
      expect(await store.loadShareLink(), isNull);
    });

    test('an expired link is dropped instead of returned', () async {
      final store = ResultStore();
      await store.saveShareLink(
        StoredShareLink(
          id: 'a2b3c4d5e6f7g8h9',
          token: 'f' * 48,
          url: 'https://voteaxis.org/result/a2b3c4d5e6f7g8h9',
          encrypted: false,
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      expect(await store.loadShareLink(), isNull);
    });
  });

  group('clearing', () {
    test(
      'clearEverything wipes runs, drafts, settings, and the link',
      () async {
        final store = ResultStore();
        await store.setOnboarded();
        await store.saveHomeState('MI');
        await store.saveSettings(const AppSettings(skipQuiz: true));
        await store.saveCalibrationDay('2026-08-13');
        await store.saveShareLink(
          StoredShareLink(
            id: 'a2b3c4d5e6f7g8h9',
            token: 'f' * 48,
            url: 'x',
            encrypted: false,
            expiresAt: DateTime.now().add(const Duration(days: 1)),
          ),
        );
        await store.saveRun(
          QuizRun(
            timestampMs: 1,
            issueScores: const {'taxes': -10},
            pillarScores: const {'economy': -10},
            axisScore: -10,
          ),
        );
        await store.saveProgress([1, null], 0, questionIds: const ['a', 'b']);

        await store.clearEverything();

        expect(await store.loadRuns(), isEmpty);
        expect(await store.loadProgress(), isNull);
        expect(await store.hasOnboarded(), isFalse);
        expect(await store.loadHomeState(), isNull);
        expect(await store.loadCalibrationDay(), isNull);
        expect(await store.loadShareLink(), isNull);
        expect(await store.loadSettings(), const AppSettings());
      },
    );

    test('clearResults leaves preferences and the home state alone', () async {
      final store = ResultStore();
      await store.saveHomeState('MI');
      await store.saveSettings(const AppSettings(skipQuiz: true));
      await store.saveRun(
        QuizRun(
          timestampMs: 1,
          issueScores: const {'taxes': -10},
          pillarScores: const {'economy': -10},
          axisScore: -10,
        ),
      );

      await store.clearResults();

      expect(await store.loadRuns(), isEmpty);
      expect(await store.loadHomeState(), 'MI');
      expect((await store.loadSettings()).skipQuiz, isTrue);
    });
  });
}
