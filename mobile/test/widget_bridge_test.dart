import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voteaxis/data/app_data.dart';
import 'package:voteaxis/models/issue.dart';
import 'package:voteaxis/models/issue_of_the_day.dart';
import 'package:voteaxis/models/pillar.dart';
import 'package:voteaxis/models/question.dart';
import 'package:voteaxis/services/result_store.dart';
import 'package:voteaxis/services/widget_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  final data = AppData(
    pillars: const [Pillar(id: 'economy', label: 'Economy', description: '')],
    issues: const [Issue(id: 'taxes', label: 'Taxes', pillarId: 'economy')],
    questions: const [
      Question(
        id: 'a',
        issueId: 'taxes',
        text: 'Raise top rates?',
        polarity: -1,
      ),
    ],
    politicians: const [],
  );

  const issue = IssueOfTheDay(
    issueId: 'taxes',
    headline: 'Taxes',
    question: 'Raise top rates?',
    polarity: -1,
    dayKey: '2026-08-13',
  );

  test('widget tap nudges the saved run once per calendar day', () async {
    final store = ResultStore();
    await store.saveRun(
      QuizRun(
        timestampMs: 1,
        issueScores: const {'taxes': 0},
        pillarScores: const {'economy': 0},
        axisScore: 0,
      ),
    );
    await applyWidgetCalibration(
      agree: true,
      store: store,
      data: data,
      issueOverride: issue,
      now: DateTime(2026, 8, 13),
    );
    expect((await store.latestRun())!.issueScores['taxes'], -20);
    expect(await store.loadCalibrationDay(), '2026-08-13');

    await applyWidgetCalibration(
      agree: false,
      store: store,
      data: data,
      issueOverride: issue,
      now: DateTime(2026, 8, 13),
    );
    expect((await store.latestRun())!.issueScores['taxes'], -20);
  });

  test('widget tap without a quiz does not invent a profile', () async {
    final store = ResultStore();
    await applyWidgetCalibration(
      agree: true,
      store: store,
      data: data,
      issueOverride: issue,
      now: DateTime(2026, 8, 13),
    );
    expect(await store.latestRun(), isNull);
    expect(await store.loadCalibrationDay(), isNull);
  });
}
