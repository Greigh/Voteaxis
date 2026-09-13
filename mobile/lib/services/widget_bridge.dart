import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../data/app_data.dart';
import '../models/issue_of_the_day.dart';
import '../models/question.dart';
import '../models/scoring.dart';
import 'result_store.dart';
import 'voteaxis_api.dart';

const widgetAppGroupId = 'group.com.greighstudios.voteaxis';
const widgetIosName = 'IssueWidget';
const widgetAndroidName = 'IssueWidgetProvider';
const widgetAndroidQualified = 'com.greighstudios.voteaxis.IssueWidgetProvider';

@pragma('vm:entry-point')
Future<void> onWidgetCalibration(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  await _safeSetAppGroup();
  final side = uri?.queryParameters['side'];
  if (side != 'agree' && side != 'disagree') return;
  await applyWidgetCalibration(agree: side == 'agree');
}

Future<IssueOfTheDay?> issueFromWidgetData() async {
  final issueId = await HomeWidget.getWidgetData<String>('issueId');
  if (issueId == null || issueId.isEmpty) return null;
  final polarityRaw = await HomeWidget.getWidgetData<String>('polarity');
  return IssueOfTheDay(
    issueId: issueId,
    headline:
        await HomeWidget.getWidgetData<String>('headline') ??
        'Issue of the day',
    question: await HomeWidget.getWidgetData<String>('question') ?? '',
    polarity: int.tryParse(polarityRaw ?? '') ?? -1,
    dayKey:
        await HomeWidget.getWidgetData<String>('dayKey') ??
        IssueOfTheDay.dateKey(DateTime.now()),
    source: 'widget',
  );
}

Future<void> applyWidgetCalibration({
  required bool agree,
  ResultStore? store,
  AppData? data,
  IssueOfTheWeek? week,
  DateTime? now,
  IssueOfTheDay? issueOverride,
}) async {
  final resultStore = store ?? ResultStore();
  final appData = data ?? await AppData.load();
  final today = now ?? DateTime.now();
  final day = IssueOfTheDay.dateKey(today);
  var issue = issueOverride;
  if (issue == null) {
    try {
      issue = await issueFromWidgetData();
    } catch (_) {
      issue = null;
    }
  }
  issue ??= IssueOfTheDay.resolve(
    week: week,
    questions: appData.questions,
    now: today,
  );
  final latest = await resultStore.latestRun();
  if (latest == null) {
    await publishIssueWidget(
      issue: issue,
      hasProfile: false,
      status: 'needQuiz',
    );
    return;
  }
  if (await resultStore.loadCalibrationDay() == day) {
    await publishIssueWidget(
      issue: issue,
      hasProfile: true,
      status: 'saved',
      axisLabel: Scoring.formatScore(latest.toProfile().axisScore),
    );
    return;
  }
  final updated = Scoring.applyMicroCalibration(
    profile: latest.toProfile(),
    issues: appData.issues,
    issueId: issue.issueId,
    polarity: issue.polarity,
    agree: agree,
  );
  await resultStore.replaceLatestRun(
    QuizRun.fromProfile(updated, label: latest.label),
  );
  await resultStore.saveCalibrationDay(day);
  await publishIssueWidget(
    issue: issue,
    hasProfile: true,
    status: 'saved',
    axisLabel: Scoring.formatScore(updated.axisScore),
  );
}

Future<void> initIssueWidget() async {
  try {
    await HomeWidget.setAppGroupId(widgetAppGroupId);
    await HomeWidget.registerInteractivityCallback(onWidgetCalibration);
  } catch (_) {}
}

Future<void> syncIssueWidget({
  required List<Question> questions,
  IssueOfTheWeek? week,
  required bool hasProfile,
  String? axisLabel,
  DateTime? now,
}) async {
  final issue = IssueOfTheDay.resolve(
    week: week,
    questions: questions,
    now: now,
  );
  final already = await ResultStore().loadCalibrationDay() == issue.dayKey;
  await publishIssueWidget(
    issue: issue,
    hasProfile: hasProfile,
    status: !hasProfile
        ? 'needQuiz'
        : already
        ? 'saved'
        : 'ready',
    axisLabel: axisLabel,
  );
}

Future<void> publishIssueWidget({
  required IssueOfTheDay issue,
  required bool hasProfile,
  required String status,
  String? axisLabel,
}) async {
  try {
    await HomeWidget.setAppGroupId(widgetAppGroupId);
    await HomeWidget.saveWidgetData<String>('headline', issue.headline);
    await HomeWidget.saveWidgetData<String>('question', issue.question);
    await HomeWidget.saveWidgetData<String>('issueId', issue.issueId);
    await HomeWidget.saveWidgetData<String>('polarity', '${issue.polarity}');
    await HomeWidget.saveWidgetData<String>('dayKey', issue.dayKey);
    await HomeWidget.saveWidgetData<String>(
      'hasProfile',
      hasProfile ? '1' : '0',
    );
    await HomeWidget.saveWidgetData<String>('status', status);
    await HomeWidget.saveWidgetData<String>('axisLabel', axisLabel ?? '');
    await HomeWidget.updateWidget(
      name: widgetAndroidName,
      iOSName: widgetIosName,
      qualifiedAndroidName: widgetAndroidQualified,
    );
  } catch (_) {}
}

Future<void> _safeSetAppGroup() async {
  try {
    await HomeWidget.setAppGroupId(widgetAppGroupId);
  } catch (_) {}
}
